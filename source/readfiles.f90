!Copyright (C) 2013- Roger Wesson
!Free under the terms of the GNU General Public License v3

module mod_readfiles
use mod_types
use mod_routines

contains

subroutine readdata(spectrumfile, spectrum_1d, spectrum_2d, spectrum_3d, wavelengths, wavelengthscaling, axes)
!take the filename, check if it's FITS or plain text
!if FITS, then read the necessary keywords to set the wavelength scale, allocate the data array according to the number of dimensions found, and fill it
!if plain text, read two columns for wavelength and flux, return.

  implicit none
  character (len=*), intent(in) :: spectrumfile !input file name
  real, dimension(:), allocatable :: wavelengths !wavelength array
  real, dimension(:), allocatable :: spectrum_1d !array for 1d data
  real, dimension(:,:), allocatable :: spectrum_2d !array for 2d data
  real, dimension(:,:,:), allocatable :: spectrum_3d !array for 3d data
  real :: wavelength, dispersion, referencepixel
  real :: wavelengthscaling !factor to convert wavelengths into Angstroms
  logical :: loglambda !is the spectrum logarithmically sampled?
  integer :: dimensions !number of dimensions
  integer, dimension(:), allocatable :: axes !number of pixels in each dimension
  integer :: i, io !counter and io status for file reading

  !cfitsio variables

  integer :: status,unit,readwrite,blocksize,hdutype,group
  character(len=80) :: key_cunit, key_ctype, key_crpix, key_crval, key_cdelt, key_cd
  character(len=80) :: cunit,ctype
  real :: nullval
  logical :: anynull

#ifdef CO
  print *,"subroutine: readdata"
#endif

  !is the file a FITS file?
  !if it contains the string .fit or .FIT, assume that it is.

  if (index(spectrumfile,".fit").gt.0 .or. index(spectrumfile,".FIT").gt.0) then !read header
    print *,"looks like a FITS file"
    status=0
    !  Get an unused Logical Unit Number to use to open the FITS file.
    call ftgiou(unit,status)
    !  Open the FITS file
    readwrite=0
    call ftopen(unit,trim(spectrumfile),readwrite,blocksize,status)

    if (status .ne. 0) then
      print *,gettime(),"error: couldn't open FITS file ",trim(spectrumfile),". CFITSIO error code was ",status
      call exit(1)
    endif

    ! get number of axes
    dimensions=0
    call ftgidm(unit,dimensions,status)
    do while (dimensions .eq. 0) ! if no axes found in first extension, advance and check again
      call ftmrhd(unit,1,hdutype,status)
      call ftgidm(unit,dimensions,status)
    enddo
    if (dimensions .eq. 0) then ! still no axes found
      print *,gettime(),"error : no axes found in ",trim(spectrumfile)
      call exit(1)
    elseif (dimensions .gt. 3) then ! can't imagine what a 4D fits file would actually be, but alfa definitely can't handle it
      print *,gettime(),"error : more than 3 axes found in ",trim(spectrumfile)
      call exit(1)
    endif

    print *,gettime(),"  number of dimensions: ",dimensions

    ! now get the dimensions of the axis

    allocate(axes(dimensions))
    call ftgisz(unit,dimensions,axes,status)

    ! set up array for wavelengths

    if (dimensions.eq.3) then
      allocate(wavelengths(axes(3)))
    else
      allocate(wavelengths(axes(1)))
    endif

    ! get wavelength, dispersion and reference pixel
    ! set which FITS keywords we are looking for depending on which axis represents wavelength
    ! this will be axis 3 for cubes, axis 1 otherwise

    status=0

    if (dimensions .lt. 3) then

      key_crval="CRVAL1"
      key_crpix="CRPIX1"
      key_ctype="CTYPE1"
      key_cunit="CUNIT1"
      key_cdelt="CDELT1"
      key_cd   ="CD1_1"

    else

      key_crval="CRVAL3"
      key_crpix="CRPIX3"
      key_ctype="CTYPE3"
      key_cunit="CUNIT3"
      key_cdelt="CDELT3"
      key_cd   ="CD3_3"

    endif

    call ftgkye(unit,key_crval,wavelength,"",status)
    if (status .ne. 0) then
      print *,gettime(),"error: couldn't find wavelength value at reference pixel - no keyword ",trim(key_crval),"."
      call exit(1)
    endif

    print *,gettime(),"  wavelength at reference pixel: ",wavelength

    call ftgkye(unit,key_crpix,referencepixel,"",status)
    if (status .ne. 0) then
      print *,gettime(),"warning: couldn't find reference pixel - no keyword ",trim(key_crpix),". Setting to 1.0"
      referencepixel=1.0
      status=0
    endif

    print *,gettime(),"  reference pixel: ",referencepixel

    call ftgkye(unit,key_cdelt,dispersion,"",status)
    if (status.ne.0) then
      status=0
      call ftgkye(unit,key_cd,dispersion,"",status)
        if (status .ne. 0) then
          print *,gettime(),"error: couldn't find wavelength dispersion - no keyword ",trim(key_cdelt)," or ",trim(key_cd),"."
          call exit(1)
        endif
    endif

    print *,gettime(),"  wavelength dispersion: ",dispersion

    ! check if the wavelength axis is log-sampled
    call ftgkey(unit,key_ctype,ctype,"",status)
    if (index(ctype,"-LOG").gt.0) then
      loglambda = .true.
      print *,gettime(),"  sampling: logarithmic"
    else
      loglambda = .false.
      print *,gettime(),"  sampling: linear"
    endif

    ! get units of wavelength
    ! current assumption is it will be A or nm

    if (wavelengthscaling .ne. 0.d0) then
      print *,gettime(),"  wavelength units: set by user. Angstroms per wavelength unit = ",wavelengthscaling
    else
      call ftgkys(unit,key_cunit,cunit,"",status)
      if (trim(cunit) .eq. "nm" .or. trim(cunit) .eq. "NM") then
        wavelengthscaling=10.d0 ! convert to Angstroms if it's in nm
        print *,gettime(),"  wavelength units: nm.  Will convert to A."
      elseif (trim(cunit).eq."Angstrom" .or. trim(cunit).eq."Angstroms") then
        print *,gettime(),"  wavelength units: Angstroms"
        wavelengthscaling = 1.d0
      else
        print *,gettime(),"  wavelength units: not recognised - will assume A.  Set the --wavelength-scaling if this is not correct"
        wavelengthscaling = 1.d0
      endif
    endif

    !now we have the information we need to read in the data

    group=1
    nullval=-999

    if (dimensions.eq.1) then

      allocate(spectrum_1d(axes(1)))

      status = 0
      call ftgpve(unit,group,1,axes(1),nullval,spectrum_1d,anynull,status)
      !todo: report null values?
      if (status .eq. 0) then
        print "(X,A,A,I7,A)",gettime(),"read 1D fits file with ",axes(1)," data points into memory."
      else
        print *,gettime(),"couldn't read file into memory"
        call exit(1)
      endif

    elseif (dimensions.eq.2) then

      allocate(spectrum_2d(axes(1),axes(2)))

      status=0
      call ftg2de(unit,group,nullval,axes(1),axes(1),axes(2),spectrum_2d,anynull,status)
    !todo: report null values?
      if (status .eq. 0) then
        print "(X,A,A,I7,A)",gettime(),"read ",axes(2)," rows into memory."
      else
        print *,gettime(),"couldn't read RSS file into memory"
        print *,"error code ",status
        call exit(1)
      endif

    elseif (dimensions.eq.3) then

      allocate(spectrum_3d(axes(1),axes(2),axes(3)))

      status=0
      call ftg3de(unit,group,nullval,axes(1),axes(2),axes(1),axes(2),axes(3),spectrum_3d,anynull,status)
    !todo: report null values?
      if (status .eq. 0) then
        print "(X,A,A,I7,A)",gettime(),"read ",axes(1)*axes(2)," pixels into memory."
      else
        print *,gettime(),"couldn't read cube into memory"
        call exit(1)
      endif

    else

      print *,gettime(),"More than 3 dimensions.  ALFA cannot comprehend that yet, sorry."
      call exit(1)

    endif

    ! calculate wavelength array

    if (loglambda) then !log-sampled case
      do i=1,size(wavelengths)
        wavelengths(i) = wavelengthscaling * wavelength*exp((i-referencepixel)*dispersion/wavelength)
      enddo
    else !linear case
      do i=1,size(wavelengths) 
        wavelengths(i) = wavelengthscaling * (wavelength+(i-referencepixel)*dispersion)
      enddo
    endif

  else ! end of FITS file loop. if we are here, assume file is 1D ascii with wavelength and flux columns.

    allocate(axes(1))

    !get number of lines

    i = 0
    open(199, file=spectrumfile, iostat=IO, status='old')
      do while (IO >= 0)
      read(199,*,end=112)
      i = i + 1
    enddo
    112 axes(1) = i
    print *,gettime(),"  number of data points: ",axes(1)

    !then allocate and read

    allocate(spectrum_1d(axes(1)))
    allocate(wavelengths(axes(1)))

    rewind (199)
    do i=1,axes(1)
      read(199,*) wavelengths(i), spectrum_1d(i)
    enddo
    close(199)

    if (wavelengthscaling .eq. 0.d0) then
      print *,gettime(),"  wavelength units: assumed to be Angstroms"
      wavelengthscaling = 1.d0
    else
      print *,gettime(),"  wavelength units: set by user. Angstroms per wavelength unit = ",wavelengthscaling
    endif

    wavelengths = wavelengths * wavelengthscaling

  endif

  print *,gettime(),"wavelength range: ",wavelengths(1),wavelengths(size(wavelengths))
  print *

end subroutine readdata

subroutine readlinelist(linelistfile,referencelinelist,nlines,wavelength1, wavelength2)
!this subroutine reads in the line catalogue
! - linelistfile is the name of the line catalogue file
! - referencelinelist is the array into which the values are read
! - nlines is the number of lines successfully read into the array
! - wavelength1 and wavelength2 define the range of wavelenths to be read in

  implicit none
  character (len=512) :: linelistfile
  character (len=85) :: linedatainput
  integer :: i
  real :: input1, wavelength1, wavelength2
  integer :: io, nlines
  logical :: file_exists

  type(linelist), dimension(:), allocatable :: referencelinelist

#ifdef CO
  print *,"subroutine: readlinelist"
#endif

  ! deallocate if necessary
  if (allocated(referencelinelist)) deallocate(referencelinelist)

  if (trim(linelistfile)=="") then
    print *,gettime(),"error: No line catalogue specified"
    call exit(1)
  endif

  inquire(file=linelistfile, exist=file_exists) ! see if the input file is present

  if (.not. file_exists) then
    print *,gettime(),"error: line catalogue ",trim(linelistfile)," does not exist"
    call exit(1)
  else
    I = 0
    OPEN(199, file=linelistfile, iostat=IO, status='old')
    DO WHILE (IO >= 0)
      READ(199,*,end=110) input1
      if (input1 .ge. wavelength1 .and. input1 .le.  wavelength2) then
      !only read in lines that lie within the observed wavelength range
        I = I + 1
      endif
    END DO
    110     nlines=I
  endif

!then allocate and read

  allocate(referencelinelist(nlines))

  REWIND (199)
  I=1
  do while (i .le. nlines)
    READ(199,'(F7.3,A)') input1, linedatainput
    if (input1 .ge. wavelength1 .and. input1 .le. wavelength2) then
      referencelinelist(i)%wavelength = input1
      referencelinelist(i)%peak=1000.
!formerly abs(realspec(minloc((realspec%wavelength-input1)**2,1))%flux) but in case of weak lines near to negative flux values this prevented them being fitted. it makes a negligible difference to the running time
      referencelinelist(i)%linedata = linedatainput
      i=i+1
    endif
    if (input1 .ge.  wavelength2) then
      exit
    endif
  END DO
  CLOSE(199)

end subroutine readlinelist

subroutine selectlines(referencelinelist,wavelength1,wavelength2,fittedlines,nlines)
!creates the array fittedlines, which contains the lines from referencelinelist which lie between wavelength1 and wavelength2

  implicit none
  real :: wavelength1, wavelength2
  integer :: startloc,nlines

  type(linelist), dimension(:), allocatable :: referencelinelist, fittedlines

#ifdef CO
  print *,"subroutine: selectlines: ",wavelength1,wavelength2
#endif

!deallocate if necessary
  if (allocated(fittedlines)) deallocate(fittedlines)

!then copy the relevant lines
  nlines=count(referencelinelist%wavelength.gt.wavelength1 .and. referencelinelist%wavelength.le.wavelength2)
  if (nlines .gt. 0) then
    allocate(fittedlines(nlines))
    startloc=minloc(referencelinelist%wavelength-wavelength1,1,referencelinelist%wavelength-wavelength1.gt.0)
    fittedlines=referencelinelist(startloc:startloc+nlines-1)
  endif

end subroutine selectlines
end module mod_readfiles
