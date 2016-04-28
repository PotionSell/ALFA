program alfa

use mod_readfiles
use mod_routines
use mod_types
use mod_continuum
use mod_fit
use mod_uncertainties
use mod_commandline

implicit none
integer :: I, spectrumlength, nlines, linearraypos, totallines, startpos, endpos
real :: startwlen, endwlen
character (len=512) :: spectrumfile,stronglinelistfile,deeplinelistfile,skylinelistfile,outputdirectory,outputbasename

type(linelist), dimension(:), allocatable :: skylines_catalogue, stronglines_catalogue, deeplines_catalogue
type(linelist), dimension(:), allocatable :: fittedlines, fittedlines_section, skylines, skylines_section
type(spectrum), dimension(:), allocatable :: realspec, fittedspectrum, spectrumchunk, skyspectrum, continuum, stronglines

integer :: filetype, dimensions
real :: wavelength, dispersion, baddata
integer :: cube_i, cube_j, cube_k, rss_i, rss_k
integer, dimension(:), allocatable :: axes
real, dimension(:,:), allocatable :: rssdata
real, dimension(:,:,:), allocatable :: cubedata
real :: minimumwavelength,maximumwavelength ! limits of spectrum, to be passed to catalogue reading subroutines

CHARACTER(len=2048) :: commandline

real :: redshiftguess, resolutionguess, redshiftguess_overall
real :: vtol1, vtol2, rtol1, rtol2
real :: blendpeak
real :: normalisation, hbetaflux
real :: c
integer :: linelocation, overlap
integer :: generations, popsize
real :: pressure

logical :: normalise=.false. !false means spectrum normalised to whatever H beta is detected, true means spectrum normalised to user specified value
logical :: resolution_estimated=.false. !true means user specified a value, false means estimate from sampling
logical :: subtractsky=.false. !attempt to fit night sky emission lines
logical :: file_exists

logical :: messages

character(len=12) :: fluxformat !for writing out the line list

! openmp variables

integer :: tid, omp_get_thread_num, omp_get_num_threads

c=299792.458 !km/s
!default values in absence of user specificed guess
redshiftguess=0.0 !km/s
resolutionguess=0.0 !lambda/deltalambda, determined assuming nyquist sampling if not specified
rtol1=0.d0 !variation allowed in resolution on first pass.  determined later, either from user input, or to be equal to resolution guess.
rtol2=500. !second pass
vtol1=0.003 !variation allowed in velocity (expressed as redshift) on first pass. 0.003 = 900 km/s
vtol2=0.0002 !second pass. 0.0002 = 60 km/s
baddata=0.d0

stronglinelistfile=trim(PREFIX)//"/share/alfa/strong.cat"
deeplinelistfile=trim(PREFIX)//"/share/alfa/deep.cat"
skylinelistfile=trim(PREFIX)//"/share/alfa/sky.cat"

outputdirectory="./"

messages=.false.

popsize=30
pressure=0.3 !pressure * popsize needs to be an integer
generations=500

! start

print *,"ALFA, the Automated Line Fitting Algorithm"
print *,"------------------------------------------"

print *
print *,gettime(),": starting code"

! random seed

call init_random_seed()

! read command line

call readcommandline(commandline,normalise,normalisation,redshiftguess,resolutionguess,vtol1,vtol2,rtol1,rtol2,baddata,pressure,spectrumfile,outputdirectory,skylinelistfile,stronglinelistfile,deeplinelistfile,generations,popsize,subtractsky,resolution_estimated,file_exists)

! convert from velocity to redshift

redshiftguess=1.+(redshiftguess/c)

! read in spectrum to fit and line list

print *,gettime(),": reading in file ",trim(spectrumfile)
call getfiletype(spectrumfile,filetype,dimensions,axes,wavelength,dispersion) !call subroutine to determine whether it's 1D, 2D or 3D fits, or ascii, or none of the above
if (filetype.eq.1) then !1d fits file
  spectrumlength=axes(1)
  call read1dfits(spectrumfile, realspec, spectrumlength, fittedspectrum, wavelength, dispersion)
  minimumwavelength=realspec(1)%wavelength
  maximumwavelength=realspec(spectrumlength)%wavelength
  if (maxval(realspec%flux) .lt. baddata) then
    print *,gettime(),": no good data in spectrum (all fluxes are less than ",baddata,")"
    stop
  endif
  messages=.true.
elseif (filetype .eq. 2) then !2d fits file
  call read2dfits(spectrumfile, rssdata, dimensions, axes)
  minimumwavelength=wavelength
  maximumwavelength=wavelength+(axes(1)-1)*dispersion
elseif (filetype .eq. 3) then !3d fits file
  call read3dfits(spectrumfile, cubedata, dimensions, axes)
  minimumwavelength=wavelength
  maximumwavelength=wavelength+(axes(3)-1)*dispersion
elseif (filetype .eq. 4) then !1d ascii file
  call readascii(spectrumfile, realspec, spectrumlength, fittedspectrum)
  minimumwavelength=realspec(1)%wavelength
  maximumwavelength=realspec(spectrumlength)%wavelength
  if (maxval(realspec%flux) .lt. baddata) then
    print *,gettime(),": no good data in spectrum (all fluxes are less than ",baddata,")"
    stop
  endif
  messages=.true.
else
  !not recognised, stop
  print *,"unrecognised file"
  stop
endif

!read in catalogues

print *,gettime(),": reading in line catalogues"
call readlinelist(skylinelistfile, skylines_catalogue, nlines,minimumwavelength,maximumwavelength)
call readlinelist(stronglinelistfile, stronglines_catalogue, nlines,minimumwavelength,maximumwavelength)
call readlinelist(deeplinelistfile, deeplines_catalogue, nlines,minimumwavelength,maximumwavelength)

if (filetype .eq. 1 .or. filetype .eq. 4) then !fit 1D data
  tid=0
  include "spectralfit.f95"
elseif (filetype .eq. 2) then !fit 2D data

!$OMP PARALLEL private(spectrumfile,outputbasename,realspec,fittedspectrum,spectrumlength,continuum,nlines,spectrumchunk,linearraypos,overlap,startpos,startwlen,endpos,endwlen,skylines,skylines_section,stronglines,fittedlines,fittedlines_section,blendpeak,hbetaflux,totallines,skyspectrum,redshiftguess_overall,rss_i,tid) firstprivate(redshiftguess,resolutionguess) shared(skylines_catalogue,stronglines_catalogue,deeplines_catalogue, axes)
!$OMP MASTER
  if (omp_get_num_threads().gt.1) then
    print "(X,A9,X,A,I2,A)",gettime(), ": using ",omp_get_num_threads()," processors"
  endif
!$OMP END MASTER

!$OMP DO schedule(dynamic)
  do rss_i=1,axes(2)

    tid=OMP_GET_THREAD_NUM()

    write (spectrumfile,"(A4,I5.5,A4)") "row_",rss_i,".dat"
    allocate(realspec(axes(1)))
    spectrumlength=axes(1)
    realspec%flux=rssdata(:,rss_i)
    do rss_k=1,axes(1)
      realspec(rss_k)%wavelength=wavelength+(rss_k-1)*dispersion
    enddo

!check for valid data
!ultra crude at the moment

    inquire(file=trim(outputdirectory)//trim(spectrumfile)//"_lines", exist=file_exists)

    if (maxval(realspec%flux) .lt. baddata .or. file_exists) then
      print "(X,A,A,I2,A,I5.5,A,I5.5)",gettime(), "(thread ",tid,") : skipped row  ",rss_i
      deallocate(realspec)
      cycle
    endif

    allocate (fittedspectrum(spectrumlength))
    fittedspectrum%wavelength=realspec%wavelength
    fittedspectrum%flux=0.d0

!now do the fitting

    include "spectralfit.f95"

!deallocate arrays ready for the next pixel
    deallocate(realspec)
    deallocate(fittedspectrum)
    deallocate(continuum)
    if (allocated(skyspectrum)) deallocate(skyspectrum)

    print "(X,A,A,I2,A,I5.5,A,I5.5)",gettime(), "(thread ",tid,") : finished row ",rss_i

  enddo

!$OMP END DO
!$OMP END PARALLEL

  print *,gettime(), ": all processing finished"

  deallocate(rssdata)

elseif (filetype .eq. 3) then !fit 3D data
!process cube
  print *,gettime(),": processing cube"
!$OMP PARALLEL private(spectrumfile,outputbasename,realspec,fittedspectrum,spectrumlength,continuum,nlines,spectrumchunk,linearraypos,overlap,startpos,startwlen,endpos,endwlen,skylines,skylines_section,stronglines,fittedlines,fittedlines_section,blendpeak,hbetaflux,totallines,skyspectrum,redshiftguess_overall,cube_i,cube_j,tid) firstprivate(redshiftguess,resolutionguess) shared(skylines_catalogue,stronglines_catalogue,deeplines_catalogue, axes)

!$OMP MASTER
  if (omp_get_num_threads().gt.1) then
    print "(X,A9,X,A,I2,A)",gettime(), ": using ",omp_get_num_threads()," processors"
  endif
!$OMP END MASTER

!$OMP DO schedule(dynamic)
  do cube_i=1,axes(1)
    do cube_j=1,axes(2)

      tid=OMP_GET_THREAD_NUM()

      write (spectrumfile,"(A5,I3.3,A1,I3.3,A4)") "spec_",cube_i,"_",cube_j,".dat"
      allocate(realspec(axes(3)))
      spectrumlength=axes(3)
      realspec%flux=cubedata(cube_i,cube_j,:)
      do cube_k=1,axes(3)
        realspec(cube_k)%wavelength=wavelength+(cube_k-1)*dispersion
      enddo

!check for valid data
!ultra crude and tailored for NGC 7009 at the moment
!    baddata=20000.
      baddata=0.
      inquire(file=trim(outputdirectory)//trim(spectrumfile)//"_lines", exist=file_exists)

      if (maxval(realspec%flux) .lt. baddata .or. file_exists) then
        print "(X,A,A,I2,A,I3.3,A,I3.3)",gettime(), "(thread ",tid,") : skipped pixel  ",cube_i,",",cube_j
        deallocate(realspec)
        cycle
      endif

      allocate (fittedspectrum(spectrumlength))
      fittedspectrum%wavelength=realspec%wavelength
      fittedspectrum%flux=0.d0

!now do the fitting

      include "spectralfit.f95"

!deallocate arrays ready for the next pixel

      deallocate(realspec)
      deallocate(fittedspectrum)
      deallocate(continuum)
      if (allocated(skyspectrum)) deallocate(skyspectrum)

      print "(X,A,A,I2,A,I3.3,A,I3.3)",gettime(), "(thread ",tid,") : finished pixel ",cube_i,",",cube_j

    enddo
  enddo

!$OMP END DO
!$OMP END PARALLEL

  print *,gettime(), ": all processing finished"

  deallocate(cubedata)

endif

!free memory

if (allocated(rssdata)) deallocate(rssdata)
if (allocated(cubedata)) deallocate(cubedata)

print *,gettime(),": all done"
print *

end program alfa
