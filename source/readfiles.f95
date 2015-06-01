module mod_readfiles
use mod_types
use mod_routines

contains

subroutine readspectrum(spectrumfile, realspec, spectrumlength, fittedspectrum)

  implicit none
  character (len=512) :: spectrumfile
  integer :: i
  real :: input1, input2
  integer :: io, spectrumlength
  logical :: file_exists

  type(spectrum), dimension(:), allocatable :: realspec, fittedspectrum

  !read in spectrum to fit

  if (trim(spectrumfile)=="") then
    print *,gettime(),": error: No input spectrum specified"
    stop
  endif

  inquire(file=spectrumfile, exist=file_exists) ! see if the input file is present

  if (.not. file_exists) then
    print *,gettime(),": error: input spectrum ",trim(spectrumfile)," does not exist"
    stop
  else
    I = 0
    OPEN(199, file=spectrumfile, iostat=IO, status='old')
      DO WHILE (IO >= 0)
      READ(199,*,end=112) input1
      I = I + 1
    END DO
    112 spectrumlength=I
  endif

  !then allocate and read

  allocate (realspec(spectrumlength))
  allocate (fittedspectrum(spectrumlength))

  REWIND (199)
  DO I=1,spectrumlength
    READ(199,*) input1, input2
    realspec(i)%wavelength = input1
    realspec(i)%flux = input2
    realspec(i)%uncertainty = 0.d0
  END DO
  CLOSE(199)

end subroutine readspectrum

subroutine readlinelist(linelistfile,referencelinelist,nlines,fittedlines, realspec)

  implicit none
  character (len=512) :: linelistfile
  character (len=85) :: linedatainput
  integer :: i
  real :: input1
  integer :: io, nlines
  logical :: file_exists

  type(linelist), dimension(:), allocatable :: referencelinelist, fittedlines
  type(spectrum), dimension(:), allocatable :: realspec

  ! deallocate if necessary
  if (allocated(referencelinelist)) deallocate(referencelinelist)
  if (allocated(fittedlines)) deallocate(fittedlines)

  if (trim(linelistfile)=="") then
    print *,gettime(),": error: No line catalogue specified"
    stop
  endif

  inquire(file=linelistfile, exist=file_exists) ! see if the input file is present

  if (.not. file_exists) then
    print *,gettime(),": error: line catalogue ",trim(linelistfile)," does not exist"
    stop
  else
    I = 0
    OPEN(199, file=linelistfile, iostat=IO, status='old')
    DO WHILE (IO >= 0)
      READ(199,*,end=110) input1
      if (input1 .ge. minval(realspec%wavelength) .and. input1 .le.  maxval(realspec%wavelength)) then
      !only read in lines that lie within the observed wavelength range
        I = I + 1
      endif
    END DO
    110     nlines=I
  endif

!then allocate and read

  allocate(referencelinelist(nlines))
  allocate(fittedlines(nlines))

  REWIND (199)
  I=1
  do while (i .le. nlines)
    READ(199,'(F7.3,A)') input1, linedatainput
    if (input1 .ge. minval(realspec%wavelength)) then
      referencelinelist(i)%wavelength = input1
      referencelinelist(i)%peak=1.
!formerly abs(realspec(minloc((realspec%wavelength-input1)**2,1))%flux) but in case of weak lines near to negative flux values this prevented them being fitted. it makes a negligible difference to the running time
      referencelinelist(i)%linedata = linedatainput
      i=i+1
    endif
    if (input1 .ge.  maxval(realspec%wavelength)) then
      exit
    endif
  END DO
  CLOSE(199)

end subroutine readlinelist
end module mod_readfiles
