!=================================================================================================================================
! Copyright (c) 2016  Prof. Claus-Dieter Munz 
! This file is part of FLEXI, a high-order accurate framework for numerically solving PDEs with discontinuous Galerkin methods.
! For more information see https://www.flexi-project.org and https://nrg.iag.uni-stuttgart.de/
!
! FLEXI is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License 
! as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
!
! FLEXI is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty
! of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License v3.0 for more details.
!
! You should have received a copy of the GNU General Public License along with FLEXI. If not, see <http://www.gnu.org/licenses/>.
!=================================================================================================================================
#include "flexi.h"

MODULE MOD_FFT
! MODULES
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
PRIVATE
!-----------------------------------------------------------------------------------------------------------------------------------
! GLOBAL VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! Private Part ---------------------------------------------------------------------------------------------------------------------
! Public Part ----------------------------------------------------------------------------------------------------------------------

INTERFACE InitFFT
  MODULE PROCEDURE InitFFT
END INTERFACE

INTERFACE FinalizeFFT
  MODULE PROCEDURE FinalizeFFT
END INTERFACE

INTERFACE ComputeFFT_R2C
  MODULE PROCEDURE ComputeFFT_R2C
END INTERFACE

INTERFACE ComputeFFT_C2R
  MODULE PROCEDURE ComputeFFT_C2R
END INTERFACE

INTERFACE Interpolate_DG2FFT
  MODULE PROCEDURE Interpolate_DG2FFT
END INTERFACE


PUBLIC:: InitFFT,FinalizeFFT
PUBLIC:: ComputeFFT_R2C,ComputeFFT_C2R
PUBLIC:: Interpolate_DG2FFT

CONTAINS

!===================================================================================================================================
!> Initialize FFT. Define necessary parameters, allocate arrays for solution and auxiliary FFT variables.
!===================================================================================================================================
SUBROUTINE InitFFT()
! MODULES
USE MOD_Globals
USE MOD_PreProc
USE MOD_analyze_hit_vars
#if USE_OPENMP
USE OMP_Lib
USE FFTW3
#endif
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER  :: i,j,k
#if USE_OPENMP
INTEGER  :: void
#endif
!===================================================================================================================================
SWRITE(UNIT_StdOut,'(132("-"))')
SWRITE(UNIT_stdOut,'(A)') ' INIT BASIS...'

kmax   = NINT(sqrt(REAL(3*N_FFT**2)))+1

#if USE_OPENMP
! Initialize FFTW with maximum number of OpenMP threads if enabled
void = FFTW_INIT_THREADS()
CALL FFTW_PLAN_WITH_NTHREADS(OMP_GET_MAX_THREADS())
#endif

Nc=FLOOR(REAL(N_FFT)/2.)
Endw(1)   = Nc+1
Endw(2:3) = N_FFT

! Allocate array for wave numbers
ALLOCATE(Localk(1:4,1:Endw(1),1:Endw(2),1:Endw(3)))
! Allocate an array for the physical position of the nodes per proc
ALLOCATE(Localxyz(1:3,1:N_FFT,1:N_FFT,1:N_FFT))

!$OMP PARALLEL DEFAULT(SHARED)
!$OMP DO PRIVATE(i,j,k)
! fill the wave space 
DO i=1,Endw(1)
  DO j=1,Endw(2)
    DO k=1,Endw(3)
      ! due to symmetry, only nx/2+1 kx are stored, ranging from 0..1..2... to Nx/2 (Nx/2+1 waves) e.g. Nx=7: k1=:0,1,2,3; Nx=4:0,1,2 
      localk(1,i,j,k)=i-1
      ! ny waves are stored, order: 0,1,2,..,Nyquist,..,..,-2,-1, e.g Ny=4: 0,1,2,-1, Ny=7: 0,1,2,3,-3,-2,-1
      IF (j.LE.Nc+1) THEN
        localk(2,i,j,k)=j-1
      ELSE
        localk(2,i,j,k)=-(N_FFT+1-j)
      END IF
      IF (k.LE.Nc+1) THEN
        localk(3,i,j,k)=k-1
      ELSE
        localk(3,i,j,k)=-(N_FFT+1-k)
      END IF
      localk(4,i,j,k)=NINT(SQRT(REAL(localk(1,i,j,k)*localk(1,i,j,k) &
                                    +localk(2,i,j,k)*localk(2,i,j,k) &
                                    +localk(3,i,j,k)*localk(3,i,j,k))))
    END DO
  END DO
END DO
!$OMP END DO

!$OMP DO PRIVATE(i,j,k)
DO i=1,N_FFT
  DO j=1,N_FFT
    DO k=1,N_FFT
      localxyz(1,i,j,k)=REAL((i-1))/REAL(N_FFT)
      localxyz(2,i,j,k)=REAL((j-1))/REAL(N_FFT)
      localxyz(3,i,j,k)=REAL((k-1))/REAL(N_FFT)
    END DO
  END DO
END DO
!$OMP END DO
!$OMP END PARALLEL

SWRITE(UNIT_stdOut,'(A)')' INIT BASIS DONE!'
SWRITE(UNIT_StdOut,'(132("-"))')

END SUBROUTINE InitFFT
!===================================================================================================================================
!> Finalize FFT
!===================================================================================================================================
SUBROUTINE FinalizeFFT()
! MODULES
                                                                                                      USE MOD_Globals
USE MOD_Analyze_Hit_Vars
USE FFTW3
!----------------------------------------------------------------------------------------------------------------------------------!
IMPLICIT NONE
! INPUT / OUTPUT VARIABLES 
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!===================================================================================================================================
#if USE_OPENMP
CALL FFTW_CLEANUP_THREADS()
#else
CALL FFTW_CLEANUP()
#endif
SDEALLOCATE(LocalXYZ)
SDEALLOCATE(LocalK)

END SUBROUTINE FinalizeFFT

!===================================================================================================================================
! ?
!===================================================================================================================================
SUBROUTINE ComputeFFT_R2C(nVar_In,U_Global,U_FFT)
! MODULES
USE MOD_Globals
USE MOD_ANALYZE_HIT_Vars       ,ONLY: N_FFT,Endw,plan
USE FFTW3
#if USE_OPENMP
USE OMP_Lib
#endif
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT/OUTPUT VARIABLES
INTEGER,INTENT(IN)    :: nVar_In
REAL,INTENT(IN)       :: U_Global(nVar_In,1:N_FFT  ,1:N_FFT  ,1:N_FFT  )
COMPLEX,INTENT(OUT)   :: U_FFT(   nVar_In,1:Endw(1),1:Endw(2),1:Endw(3))
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL          :: Time
INTEGER       :: iVar
REAL          :: U_r(1:N_FFT  ,1:N_FFT  ,1:N_FFT  ) ! Real global DG solution per variable
COMPLEX       :: U_c(1:Endw(1),1:Endw(2),1:Endw(3)) ! Complex FFT solution per variable
!===================================================================================================================================
SWRITE(UNIT_stdOut,'(a)',ADVANCE='NO')' COMPUTE FFT FROM PHYSICAL TO FOURIER...'
Time = OMP_FLEXITIME()

! Create plan once for local arrays and reuse it for each variable
CALL DFFTW_PLAN_DFT_R2C_3D(plan,N_FFT,N_FFT,N_FFT,U_r,U_c,FFTW_ESTIMATE)

! Compute FFT for each variable. Local arrays ensure data to be contiguous in memory.
DO iVar=1,nVar_In
  U_r = U_Global(iVar,:,:,:)
  CALL DFFTW_Execute(plan,U_r,U_c)
  U_FFT(iVar,:,:,:) = U_c
END DO

! Release resources allocated with plan
CALL DFFTW_DESTROY_PLAN(plan)

SWRITE(UNIT_stdOut,'(A,F0.3,A)',ADVANCE='YES')'DONE [',OMP_FLEXITIME()-Time,'s]'
END SUBROUTINE ComputeFFT_R2C

!===================================================================================================================================
! ?
!===================================================================================================================================
SUBROUTINE ComputeFFT_C2R(nVar_In,U_FFT,U_Global)
! MODULES
USE MOD_Globals
USE MOD_ANALYZE_HIT_Vars  ,ONLY: N_FFT,Endw,plan
USE FFTW3
#if USE_OPENMP
USE OMP_Lib
#endif
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT/OUTPUT VARIABLES
INTEGER,INTENT(IN)    :: nVar_In
COMPLEX,INTENT(IN)    :: U_FFT(   nVar_In,1:Endw(1),1:Endw(2),1:Endw(3))
REAL,INTENT(OUT)      :: U_Global(nVar_In,1:N_FFT  ,1:N_FFT  ,1:N_FFT  )
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL          :: Time
INTEGER       :: iVar
REAL          :: U_r(1:N_FFT  ,1:N_FFT  ,1:N_FFT  ) ! Real global DG solution per variable
COMPLEX       :: U_c(1:Endw(1),1:Endw(2),1:Endw(3)) ! Complex FFT solution per variable
!===================================================================================================================================
SWRITE(UNIT_stdOut,'(a)',ADVANCE='NO')' COMPUTE FFT FROM FOURIER TO PHYSICAL...'
Time = OMP_FLEXITIME()

! Create plan once for local arrays and reuse it for each variable
CALL DFFTW_PLAN_DFT_C2R_3D(plan,N_FFT,N_FFT,N_FFT,U_c,U_r,FFTW_ESTIMATE)

! Compute FFT for each variable. Local arrays ensure data to be contiguous in memory.
DO iVar=1,nVar_In
  U_c = U_FFT(iVar,:,:,:)
  CALL DFFTW_Execute(plan,U_c,U_r)
  U_Global(iVar,:,:,:) = U_r
END DO

! Release resources allocated with plan
CALL DFFTW_DESTROY_PLAN(plan)

! Normalize data (FFTW does not normalize FFT results)
U_Global=U_Global/REAL(N_FFT**3)

SWRITE(UNIT_stdOut,'(A,F0.3,A)',ADVANCE='YES')'DONE  [',OMP_FLEXITIME()-Time,'s]'

END SUBROUTINE ComputeFFT_C2R

!===================================================================================================================================
! Interpolate via ChangeBasis() state @ visu (equidistant) coordinates from postprocessing (CGL)
!===================================================================================================================================
SUBROUTINE Interpolate_DG2FFT(nVar_In,U_DG,U_Global)
! MODULES
USE MOD_Globals
USE MOD_PreProc
USE MOD_Analyze_HIT_Vars      ,ONLY: NodeType_HDF5
USE MOD_Analyze_HIT_Vars      ,ONLY: N_FFT,N_Visu
USE MOD_Mesh_Vars             ,ONLY: Elem_IJK,nElems
USE MOD_Interpolation         ,ONLY: GetVandermonde
USE MOD_ChangeBasis           ,ONLY: ChangeBasis3D
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT/OUTPUT VARIABLES
INTEGER,INTENT(IN)    :: nVar_In
REAL,INTENT(INOUT)    :: U_DG(    nVar_In,0:PP_N ,0:PP_N ,0:PP_N ,nElems)
REAL,INTENT(OUT)      :: U_Global(nVar_In,1:N_FFT,1:N_FFT,1:N_FFT       )
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER       :: iElem
INTEGER       :: i,ii,iGlob
INTEGER       :: j,jj,jGlob
INTEGER       :: k,kk,kGlob
REAL          :: U_aux(nVar_In,0:N_Visu,0:N_Visu,0:N_Visu)
REAL          :: VdmGaussEqui(0:N_Visu,0:PP_N)
!===================================================================================================================================
SWRITE(UNIT_stdOut,'(a)',ADVANCE='NO')' INTERPOLATE DG SOLUTION TO FFT COORDS...'

! Vandermonde to interpolate from HDF5_Nodetype to equidistant points
CALL GetVandermonde(PP_N,NodeType_HDF5,N_Visu,'VISU_INNER',VdmGaussEqui)

!$OMP PARALLEL DEFAULT(SHARED) PRIVATE(iElem,i,ii,iGlob,j,jj,jGlob,k,kk,kGlob,U_aux)
!$OMP DO
! Loop to get the nodal U_DG solution into a global solution in ijk form
DO iElem=1,nElems
  ! Get solution in each element on equidistant points
  CALL ChangeBasis3D(nVar_In,PP_N,N_Visu,VdmGaussEqui,U_DG(:,:,:,:,iElem),U_aux(:,:,:,:))

  ! Fill the global solution array using the ijk sorting
  ii=Elem_IJK(1,iElem)
  jj=Elem_IJK(2,iElem)
  kk=Elem_IJK(3,iElem)
  DO k=0,N_Visu
    kGlob=(kk-1)*(N_Visu+1)+k+1
    DO j=0,N_Visu
      jGlob=(jj-1)*(N_Visu+1)+j+1
      DO i=0,N_Visu
        iGlob=(ii-1)*(N_Visu+1)+i+1
        U_Global(:,iGlob,jGlob,kGlob) = U_aux(:,i,j,k)
      END DO
    END DO
  END DO
END DO
!$OMP END DO
!$OMP END PARALLEL

SWRITE(UNIT_stdOut,'(A)',ADVANCE='YES')'DONE'
END SUBROUTINE Interpolate_DG2FFT

END MODULE MOD_FFT
