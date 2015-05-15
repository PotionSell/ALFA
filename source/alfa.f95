program alfa

use mod_readfiles
use mod_routines
use mod_types
use mod_continuum
use mod_fit
use mod_uncertainties

implicit none
integer :: I, spectrumlength, chunklength, nlines, linearraypos, totallines
character (len=512) :: spectrumfile,linelistfile

type(linelist), dimension(:), allocatable :: referencelinelist, fittedlines, fittedlines_section
type(spectrum), dimension(:), allocatable :: realspec, fittedspectrum, spectrumchunk
type(spectrum), dimension(:), allocatable :: continuum

real :: normalisation

CHARACTER(len=2048), DIMENSION(:), allocatable :: options
CHARACTER(len=2048) :: commandline
integer :: narg

logical :: normalise

real :: redshiftguess, resolutionguess, tolerance

!set defaults

normalise = .false.

! start

print *,"ALFA, the Automated Line Fitting Algorithm"
print *,"------------------------------------------"

print *
print *,gettime(),": starting code"

! random seed

call init_random_seed()

! read command line

narg = IARGC() !count input arguments
if (narg .lt. 1) then
  print *,gettime(),": Error : file to analyse not specified"
  stop
endif

call get_command(commandline)
ALLOCATE (options(Narg))
if (narg .gt. 1) then
  do i=1,Narg-1
    call get_command_argument(i,options(i))
    if (options(i) .eq. "-n") then
      normalise = .true.
    endif
  enddo
endif

print *,gettime(),": command line: ",trim(commandline)

call get_command_argument(narg,spectrumfile)

! read in spectrum to fit and line list

print *,gettime(),": reading in spectrum ",trim(spectrumfile)
call readspectrum(spectrumfile, realspec, spectrumlength, fittedspectrum)

! then subtract the continuum

print *,gettime(),": fitting continuum"
call fit_continuum(realspec,spectrumlength, continuum)

! now do the fitting
! first get guesses for the redshift and resolution

redshiftguess=1.0000
resolutionguess=4800.
tolerance=0.5
linelistfile="linelists/strong_optical"
print *,gettime(),": reading in line catalogue ",trim(linelistfile)
call readlinelist(linelistfile, referencelinelist, nlines, fittedlines, realspec)

if (nlines .eq. 0) then
  print *,gettime(),": Error: Line catalogue does not overlap with input spectrum"
  stop
endif

print *,gettime(),": estimating resolution and redshift using ",nlines," lines"

call fit(realspec, referencelinelist, redshiftguess, resolutionguess, fittedspectrum, fittedlines, tolerance)

print *,gettime(),": estimated redshift and resolution: ",fittedlines(1)%redshift,fittedlines(1)%resolution

! then again in chunks with tighter tolerance

redshiftguess=fittedlines(1)%redshift
resolutionguess=fittedlines(1)%resolution
tolerance=0.1
linelistfile="linelists/deep_full"

linearraypos=1
!call readlinelist with full wavelength range to get total number of lines and an array to put them all in
print *,gettime(),": reading in line catalogue ",trim(linelistfile)
call readlinelist(linelistfile, referencelinelist, totallines, fittedlines, realspec)

print *, gettime(), ": fitting full spectrum with ",totallines," lines"

do i=1,spectrumlength,400

  if (spectrumlength - i .lt. 400) then
    chunklength = spectrumlength - i
  else
    chunklength = 400
  endif

  allocate(spectrumchunk(chunklength))
  spectrumchunk = realspec(i:i+chunklength-1)
  call readlinelist(linelistfile, referencelinelist, nlines, fittedlines_section, spectrumchunk)

  if (nlines .gt. 0) then
    print "(X,A,A,F6.1,A,F6.1,A,I3,A)",gettime(),": fitting from ",spectrumchunk(1)%wavelength," to ",spectrumchunk(size(spectrumchunk))%wavelength," with ",nlines," lines"
!    print *,"Best fitting model parameters:       Resolution    Redshift    RMS min      RMS max"
    call fit(spectrumchunk, referencelinelist, redshiftguess, resolutionguess, fittedspectrum(i:i+chunklength-1), fittedlines_section, tolerance)
  endif

  !copy line fitting results from chunk to main array

  deallocate(spectrumchunk)
  fittedlines(linearraypos:linearraypos+nlines-1)=fittedlines_section
  linearraypos=linearraypos+nlines

  !use redshift and resolution from this chunk as initial values for next chunk

  redshiftguess=fittedlines(1)%redshift
  resolutionguess=fittedlines(1)%resolution

enddo

! calculate the uncertainties

print *
print *,gettime(),": estimating uncertainties"
call get_uncertainties(fittedspectrum, realspec, fittedlines)

!write out line fluxes of best fitting spectrum

print *,gettime(),": writing output files ",trim(spectrumfile),"_lines.tex and ",trim(spectrumfile),"_fit"

!normalise Hb to 100 if requested

do i=1,totallines
  if (fittedlines(i)%wavelength .eq. 4861.33) then
    normalisation = 100./gaussianflux(fittedlines(i)%peak,(fittedlines(i)%wavelength/fittedlines(i)%resolution))
    exit
  endif
enddo

if (normalise) then
  print *,gettime(),": normalising to Hb=100"
else
  normalisation = 1.D0
endif

open(100,file=trim(spectrumfile)//"_lines.tex")
write(100,*) "Observed wavelength & Rest wavelength & Flux & Uncertainty & Ion & Multiplet & Lower term & Upper term & g_1 & g_2 \\"
do i=1,totallines
  if (fittedlines(i)%uncertainty .gt. 3.0) then
    write (100,"(F7.2,' & ',F7.2,' & ',F12.3,' & ',F12.3,A85,2(F12.3))") fittedlines(i)%wavelength*fittedlines(i)%redshift,fittedlines(i)%wavelength,normalisation*gaussianflux(fittedlines(i)%peak,(fittedlines(i)%wavelength/fittedlines(i)%resolution)), normalisation*gaussianflux(fittedlines(i)%peak,(fittedlines(i)%wavelength/fittedlines(i)%resolution))/fittedlines(i)%uncertainty, fittedlines(i)%linedata, (1.0-fittedlines(i)%redshift)*3.e5, fittedlines(i)%resolution
  endif
enddo
close(100)

! write out fit

open(100,file=trim(spectrumfile)//"_fit")

write (100,*) """wavelength""  ""fitted spectrum""  ""cont-subbed orig"" ""continuum""  ""residuals"""
do i=1,spectrumlength
  write(100,"(F7.2, 4(F12.3))") fittedspectrum(i)%wavelength,fittedspectrum(i)%flux*normalisation, realspec(i)%flux*normalisation, continuum(i)%flux*normalisation, (realspec(i)%flux - fittedspectrum(i)%flux)*normalisation
enddo

close(100)

print *,gettime(),": all done"

end program alfa
