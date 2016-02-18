! command line reading routine
! included in both alfa.f95 and alfa_cube.f95

call get_command(commandline)
allocate (options(Narg))

do i=1,Narg
  call get_command_argument(i,options(i))
enddo

do i=1,narg
  if ((trim(options(i))=="-n" .or. trim(options(i))=="--normalise") .and. (i+1) .le. Narg) then
    read (options(i+1),*) normalisation
    normalise=.true.
    nargused = nargused + 2
  endif
  if ((trim(options(i))=="-vg" .or. trim(options(i))=="--velocity-guess") .and. (i+1) .le. Narg) then
    read (options(i+1),*) redshiftguess
    nargused = nargused + 2
  endif
  if ((trim(options(i))=="-rg" .or. trim(options(i))=="--resolution-guess") .and. (i+1) .le. Narg) then
    read (options(i+1),*) resolutionguess
    resolution_estimated=.true.
    nargused = nargused + 2
  endif
  if ((trim(options(i))=="-vtol1" .or. trim(options(i))=="--velocity-tolerance-1") .and. (i+1) .le. Narg) then
    read (options(i+1),*) vtol1
    vtol1 = vtol1/c
    nargused = nargused + 2
  endif
  if ((trim(options(i))=="-vtol2" .or. trim(options(i))=="--velocity-tolerance-2") .and. (i+1) .le. Narg) then
    read (options(i+1),*) vtol2
    vtol2 = vtol2/c
    nargused = nargused + 2
  endif
  if ((trim(options(i))=="-rtol1" .or. trim(options(i))=="--resolution-tolerance-1") .and. (i+1) .le. Narg) then
    read (options(i+1),*) rtol1
    nargused = nargused + 2
  endif
  if ((trim(options(i))=="-rtol2" .or. trim(options(i))=="--resolution-tolerance-2") .and. (i+1) .le. Narg) then
    read (options(i+1),*) rtol2
    nargused = nargused + 2
  endif
  if (trim(options(i))=="-ss" .or. trim(options(i))=="--subtract-sky") then
    subtractsky=.true.
    nargused = nargused + 1
  endif
  if ((trim(options(i))=="-o" .or. trim(options(i))=="--output-dir") .and. (i+1) .le. Narg) then
    read (options(i+1),"(A)") outputdirectory
    outputdirectory=trim(outputdirectory)//"/"
    inquire(file=trim(outputdirectory), exist=file_exists) ! trailing slash ensures it's looking for a directory
    if (.not. file_exists) then
      print *,gettime(),": error: output directory does not exist"
      stop
    endif
    nargused = nargused + 2
  endif
  if (trim(options(i))=="-skycat" .and. (i+1) .le. Narg) then
    read (options(i+1),"(A)") skylinelistfile
    nargused = nargused + 2
  endif
  if (trim(options(i))=="-strongcat" .and. (i+1) .le. Narg) then
    read (options(i+1),"(A)") stronglinelistfile
    nargused = nargused + 2
  endif
  if (trim(options(i))=="-deepcat" .and. (i+1) .le. Narg) then
    read (options(i+1),"(A)") deeplinelistfile
    nargused = nargused + 2
  endif
  if ((trim(options(i))=="-g" .or. trim(options(i))=="--generations") .and. (i+1) .le. Narg) then
    read (options(i+1),*) generations
    nargused = nargused + 2
  endif
  if ((trim(options(i))=="-ps" .or. trim(options(i))=="--populationsize") .and. (i+1) .le. Narg) then
    read (options(i+1),*) popsize
    nargused = nargused + 2
  endif
  if ((trim(options(i))=="-pr" .or. trim(options(i))=="--pressure") .and. (i+1) .le. Narg) then
    read (options(i+1),*) pressure
    nargused = nargused + 2
  endif
! to implement:
!   continuum window and percentile
enddo

if (narg - nargused .eq. 0) then
  print *,gettime(),": error: no input file specified"
  stop
elseif (narg - nargused .gt. 1) then
  print *,gettime(),": warning: some input options were not recognised"
else
  call get_command_argument(narg,spectrumfile)
  spectrumfile=trim(spectrumfile)
endif

deallocate(options)

print *,gettime(),": ALFA is running with the following settings:"
if (.not.normalise) then
print *,"            normalisation:                    using measured value of Hb"
else
if (normalisation.eq.0.d0) then
print *,"            normalisation:                    no normalisation"
else
print *,"            normalisation:                    to Hb=",normalisation
endif
endif
print *,"            velocity guess:                   ",redshiftguess
print *,"            resolution guess:                 ",resolutionguess
print *,"            first pass velocity tolerance:    ",vtol1*c
print *,"            second pass velocity tolerance:   ",vtol2*c
print *,"            first pass resolution tolerance:  ",rtol1
print *,"            second pass resolution tolerance: ",rtol2
if (subtractsky) then
print *,"            sky line fitting:                 enabled"
print *,"            sky line catalogue:               ",trim(skylinelistfile)
else
print *,"            sky line fitting:                 disabled"
endif
print *,"            strong line catalogue:            ",trim(stronglinelistfile)
print *,"            deep line catalogue:              ",trim(deeplinelistfile)
print *,"            number of generations:            ",generations
print *,"            population size:                  ",popsize
print *,"            pressure factor:                  ",pressure
print *,"            output directory:                 ",trim(outputdirectory)
