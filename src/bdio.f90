!
! A MODULE for non numerical routines (sorting and locate)
!
! Copyright (C) 2005  Alberto Ramos <alberto@martin.ft.uam.es>
!
! This program is free software; you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by
! the Free Software Foundation; either version 2 of the License, or
! (at your option) any later version.
!
! This program is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
! GNU General Public License for more details.
!
! You should have received a copy of the GNU General Public License
! along with this program; if not, write to the Free Software
! Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307
! USA
! 

! ***************************************************
! *
MODULE ModBDio
! *
! ***************************************************
! *
! * NonNumeric routines for sorting and locating
! * data.
! *
! ***************************************************

  USE NonNumeric

  IMPLICIT NONE


  Integer, Parameter, Private :: BDIO_R_MODE=0, BDIO_W_MODE=1, BDIO_A_MODE=2, &
       & MAXFNAME = 4096, BDIO_SHORT_LEN = 256, BDIO_LONG_LEN = 4096, &
       & BDIO_MAGIC = 2147209342, BDIO_VERSION  =1

  Integer, Parameter :: BDIO_BIN_GENERIC = 0, BDIO_ASC_EXEC = 1, &
       & BDIO_BIN_INT32BE = 2, BDIO_BIN_INT32LE = 3, &
       & BDIO_BIN_INT64BE = 4, BDIO_BIN_INT64LE = 5, &
       & BDIO_BIN_F32BE   = 6, BDIO_BIN_F32LE   = 7, &
       & BDIO_BIN_F64BE   = 8, BDIO_BIN_F64LE   = 9, &
       & BDIO_ASC_GENERIC =10, BDIO_ASC_XML     =11, &
       & BDIO_BIN_INT32 = 240, BDIO_BIN_INT64 = 241, &
       & BDIO_BIN_F32   = 242, BDIO_BIN_F64   = 243


  Logical :: DEFAULT_HASH_CHECK = .False.

  Type :: BDIO
     Integer :: ifn, rcnt=0, hcnt=0, tcnt=0
     Integer :: imode ! r/w/a
     Integer (kind=8) :: startfile=-1, endfile=-1, rwpos=-1
     Logical :: lendian, opened = .False.

     Character (len=BDIO_SHORT_LEN) :: user='alberto', host='desy.de'
     
     Type (BDIO_record), pointer :: first => null(), last => null(), &
          & current => null(), lasthdr => null()
  End type BDIO

  Type :: BDIO_record
     logical :: ishdr, islong
     Integer (kind=8) :: rlen, rpos, rend, hlu, hlh, hcr, hmd 
     Integer :: rfmt = -1, ruinfo = -1, rid = -1, iver = -1, &
          & hash = 314159265

     Integer :: created, modified, hlulen, hlhlen
     Character (len=BDIO_SHORT_LEN) :: cuser, luser, chost, &
          & lhost
     Character (len=BDIO_LONG_LEN) :: info

     Type (BDIO_record), Pointer :: next => null(), prev => null()
  End type BDIO_RECORD


  Interface byteswap
     Module Procedure byteswap_int32, byteswap_int32V, byteswap_R, &
          & byteswap_RV, byteswap_DV, byteswap_D, byteswap_DZ, &
          & byteswap_DZV, byteswap_ZV, byteswap_Z, &
          & byteswap_int64, byteswap_int64V
  End Interface byteswap

  Interface BDIO_write
     Module Procedure BDIO_write_i32, BDIO_write_i64, &
          & BDIO_write_f32, BDIO_write_f64, BDIO_write_z32, &
          & BDIO_write_z64, BDIO_write_bin
  End Interface BDIO_write
  
  Interface BDIO_read
     Module Procedure BDIO_read_i32, BDIO_read_i64, &
          & BDIO_read_f32, BDIO_read_f64, BDIO_read_z32, &
          & BDIO_read_z64, BDIO_read_bin
  End Interface BDIO_read
  

  Private :: byteswap_int32, byteswap_int32V, &
       & byteswap_R, byteswap_RV, byteswap_DV, byteswap_D, byteswap_DZ, &
       & byteswap_DZV, byteswap_ZV, byteswap_Z, byteswap_int64, &
       & byteswap_int64V, Rewrite_rlen, BDIO_read_f32, BDIO_read_f64, &
       & BDIO_read_i32, BDIO_read_i64, BDIO_read_z32, BDIO_read_z64, &
       & BDIO_write_i32, BDIO_write_i64, BDIO_write_f32, BDIO_write_bin, &
       & BDIO_write_f64, BDIO_write_z32, BDIO_write_z64, BDIO_read_bin

CONTAINS

! ********************************
! *
    Subroutine BDIO_close(fbd)
! *
! ********************************
      
      Type (BDIO), Intent (inout) :: fbd
      Type (BDIO_record), pointer :: p, n

      p => fbd%first
      Do 
         If (.not.Associated(p)) Exit
         n => p%next
         Deallocate(p)
         p => n
      End Do
      Close(fbd%ifn)
      fbd%opened = .False.

      Return
    End Subroutine BDIO_close

! ********************************
! *
    Subroutine BDIO_error(fbd, routine, msg)
! *
! ********************************

      Type (BDIO), Intent (inout) :: fbd
      Character (len=*), Intent (in) :: routine, msg

      Write(0,*)'In '//Trim(routine)// ' :'
      Write(0,'(5X,1A)')Trim(msg)
      Write(0,*)
      Write(0,*)'Current Record: ', fbd%current%rid
      Stop
      
      Return
    End Subroutine BDIO_error

! ********************************
! *
    Function BDIO_write_bin(fbd,cbuf,do_chk)
! *
! ********************************

      Type (BDIO), Intent (inout) :: fbd
      Character, Intent (in) :: cbuf(:)
      Logical, Optional :: do_chk
      Integer :: BDIO_write_bin, ios

      Integer (kind=8) :: iln, nmax, is, ie, i
      Type (BDIO_record), pointer :: p
      logical :: chk
      Integer :: ibf(128)

      BDIO_write_bin = -1
      If (fbd%imode == BDIO_R_MODE) &
           & Call BDIO_error(fbd,'BDIO_Write_bin', &
           & 'Not in write mode') 

      If (Present(do_chk)) Then
         chk = do_chk
      Else
         chk = .False. ! Do not checksum binary data
      End If
      fbd%current => fbd%last
      fbd%rwpos = fbd%last%rend
      p => fbd%current
      If (  (p%rfmt /= BDIO_ASC_GENERIC).and.&
           &(p%rfmt /= BDIO_ASC_XML).and.&
           &(p%rfmt /= BDIO_BIN_GENERIC).and.&
           &(p%rfmt /= BDIO_ASC_EXEC  ) ) Then
         Call BDIO_error(fbd,'BDIO_Write_bin', &
              & 'Incorrect data type') 
      End If

      Write(fbd%ifn,Pos=fbd%rwpos,Iostat=ios)cbuf
      
      iln = fbd%current%rlen + Size(cbuf)
      CALL Rewrite_rlen(fbd, iln)
      CALL Rewrite_hdrinfo(fbd)

      nmax = size(cbuf)
      If (chk) Then
         If (mod(nmax,4_8) /= 0) Call BDIO_error(fbd,'BDIO_Write_bin', &
              & 'Binary data needs be multiple of 4bytes to checksum') 
         I = 0
         Do
            is = 1+512*I
            ie = is+512
            If (ie > nmax) ie=nmax 
            ibf = Transfer(cbuf(is:ie), ibf)
            p%hash = Hash(ibf(:(ie-is)/4), p%hash)
            If (ie == nmax) Exit
            I = I+1
         End Do
      End If

      If (ios == 0) BDIO_write_bin = Size(cbuf)

      Return
    End Function BDIO_write_bin

! ********************************
! *
    Function BDIO_write_i32(fbd,ibuf, do_chk)
! *
! ********************************

      Type (BDIO), Intent (inout) :: fbd
      Integer (kind=4), Intent (inout) :: ibuf(:)
      Logical, Optional :: do_chk
      Integer :: BDIO_write_i32, ios

      Integer (kind=8) :: iln
      Type (BDIO_record), pointer :: p
      logical :: chk

      BDIO_write_i32 = -1
      If (fbd%imode == BDIO_R_MODE) &
           & Call BDIO_error(fbd,'BDIO_Write_i32', &
           & 'Not in write mode') 

      If (Present(do_chk)) Then
         chk = do_chk
      Else
         chk = DEFAULT_HASH_CHECK
      End If

      fbd%current => fbd%last
      fbd%rwpos = fbd%last%rend
      p => fbd%current
      If (  (p%rfmt /= BDIO_BIN_INT32LE).and.&
           &(p%rfmt /= BDIO_BIN_INT32BE).and.&
           &(p%rfmt /= BDIO_BIN_INT32  ) ) Then
         Call BDIO_error(fbd,'BDIO_Write_i32', &
              & 'Incorrect data type') 
      End If

      If (  ( (p%rfmt == BDIO_BIN_INT32BE).and.(fbd%lendian) ).or. &
           &( (p%rfmt == BDIO_BIN_INT32LE).and.(.not.fbd%lendian) ) ) &
           & Then
         CALL ByteSwap(ibuf)
         Write(fbd%ifn,Pos=fbd%rwpos,Iostat=ios)ibuf
         CALL ByteSwap(ibuf)
      Else
         Write(fbd%ifn,Pos=fbd%rwpos,Iostat=ios)ibuf
      End If
      
      If (chk) p%hash = Hash(ibuf, p%hash)
      iln = fbd%current%rlen + 4_8*Size(ibuf)
      CALL Rewrite_rlen(fbd, iln)
      CALL Rewrite_hdrinfo(fbd)

      If (ios == 0) BDIO_write_i32 = Size(ibuf)

      Return
    End Function BDIO_write_i32

! ********************************
! *
    Function BDIO_write_f32(fbd,buf, do_chk)
! *
! ********************************

      Type (BDIO), Intent (inout) :: fbd
      Real (kind=4), Intent (inout) :: buf(:)
      Logical, Optional :: do_chk
      Integer :: BDIO_write_f32, ios

      Integer (kind=8) :: iln
      Type (BDIO_record), pointer :: p
      logical :: chk

      BDIO_write_f32 = -1
      If (fbd%imode == BDIO_R_MODE) &
           & Call BDIO_error(fbd,'BDIO_Read_f32', &
           & 'Not in write mode') 

      If (Present(do_chk)) Then
         chk = do_chk
      Else
         chk = DEFAULT_HASH_CHECK
      End If
      fbd%current => fbd%last
      fbd%rwpos = fbd%last%rend
      p => fbd%current
      If (  (p%rfmt /= BDIO_BIN_F32LE).and.&
           &(p%rfmt /= BDIO_BIN_F32BE).and.&
           &(p%rfmt /= BDIO_BIN_F32  ) ) Then
         Call BDIO_error(fbd,'BDIO_Write_f32', &
              & 'Incorrect data type') 
      End If

      If (  ( (p%rfmt == BDIO_BIN_F32BE).and.(fbd%lendian) ).or. &
           &( (p%rfmt == BDIO_BIN_F32LE).and.(.not.fbd%lendian) ) ) &
           & Then
         CALL ByteSwap(buf)
         Write(fbd%ifn,Pos=fbd%rwpos,Iostat=ios)buf
         CALL ByteSwap(buf)
      Else
         Write(fbd%ifn,Pos=fbd%rwpos,Iostat=ios)buf
      End If

      iln = fbd%current%rlen + 4_8*Size(buf)
      CALL Rewrite_rlen(fbd, iln)
      CALL Rewrite_hdrinfo(fbd)

      If (chk) p%hash = Hash(buf, p%hash)
      If (ios == 0) BDIO_write_f32 = Size(buf)

      Return
    End Function BDIO_write_f32

! ********************************
! *
    Function BDIO_write_i64(fbd,ibuf, do_chk)
! *
! ********************************

      Type (BDIO), Intent (inout) :: fbd
      Integer (kind=8), Intent (inout) :: ibuf(:)
      Logical, Optional :: do_chk
      Integer :: BDIO_write_i64, ios

      Integer (kind=8) :: iln
      Type (BDIO_record), pointer :: p
      logical :: chk

      BDIO_write_i64 = -1
      If (fbd%imode == BDIO_R_MODE) &
           & Call BDIO_error(fbd,'BDIO_Read_i64', &
           & 'Not in write mode') 

      If (Present(do_chk)) Then
         chk = do_chk
      Else
         chk = DEFAULT_HASH_CHECK
      End If
      fbd%current => fbd%last
      fbd%rwpos = fbd%last%rend
      p => fbd%current
      If (  (p%rfmt /= BDIO_BIN_INT64LE).and.&
           &(p%rfmt /= BDIO_BIN_INT64BE).and.&
           &(p%rfmt /= BDIO_BIN_INT64  ) ) Then
         Call BDIO_error(fbd,'BDIO_Write_i64', &
              & 'Incorrect data type') 
      End If

      If (  ( (p%rfmt == BDIO_BIN_INT64BE).and.(fbd%lendian) ).or. &
           &( (p%rfmt == BDIO_BIN_INT64LE).and.(.not.fbd%lendian) ) ) &
           & Then
         CALL ByteSwap(ibuf)
         Write(fbd%ifn,Pos=fbd%rwpos,Iostat=ios)ibuf
         CALL ByteSwap(ibuf)
      Else
         Write(fbd%ifn,Pos=fbd%rwpos,Iostat=ios)ibuf
      End If
      
      iln = fbd%current%rlen + 8_8*Size(ibuf)
      CALL Rewrite_rlen(fbd, iln)
      CALL Rewrite_hdrinfo(fbd)

      If (chk) p%hash = Hash(ibuf, p%hash)
      If (ios == 0) BDIO_write_i64 = Size(ibuf)

      Return
    End Function BDIO_write_i64

! ********************************
! *
    Function BDIO_write_f64(fbd,ibuf, do_chk)
! *
! ********************************

      Type (BDIO), Intent (inout) :: fbd
      Real (kind=8), Intent (inout) :: ibuf(:)
      Logical, Optional :: do_chk
      Integer :: BDIO_write_f64, ios

      Integer (kind=8) :: iln
      Type (BDIO_record), pointer :: p
      logical :: chk

      BDIO_write_f64 = -1
      If (fbd%imode == BDIO_R_MODE) &
           & Call BDIO_error(fbd,'BDIO_Read_if64', &
           & 'Not in write mode') 

      If (Present(do_chk)) Then
         chk = do_chk
      Else
         chk = DEFAULT_HASH_CHECK
      End If
      fbd%current => fbd%last
      fbd%rwpos = fbd%last%rend
      p => fbd%current
      If (  (p%rfmt /= BDIO_BIN_F64LE).and.&
           &(p%rfmt /= BDIO_BIN_F64BE).and.&
           &(p%rfmt /= BDIO_BIN_F64  ) ) Then
         Call BDIO_error(fbd,'BDIO_Write_f64', &
              & 'Incorrect data type') 
      End If

      If (  ( (p%rfmt == BDIO_BIN_F64BE).and.(fbd%lendian) ).or. &
           &( (p%rfmt == BDIO_BIN_F64LE).and.(.not.fbd%lendian) ) ) &
           & Then
         CALL ByteSwap(ibuf)
         Write(fbd%ifn,Pos=fbd%rwpos,Iostat=ios)ibuf
         CALL ByteSwap(ibuf)
      Else
         Write(fbd%ifn,Pos=fbd%rwpos,Iostat=ios)ibuf
      End If
      
      iln = fbd%current%rlen + 8_8*Size(ibuf)
      CALL Rewrite_rlen(fbd, iln)
      CALL Rewrite_hdrinfo(fbd)

      If (do_chk) p%hash = Hash(ibuf, p%hash)
      If (ios == 0) BDIO_write_f64 = Size(ibuf)

      Return
    End Function BDIO_write_f64
    
! ********************************
! *
    Function BDIO_write_z64(fbd,buf,do_chk)
! *
! ********************************

      Type (BDIO), Intent (inout) :: fbd
      Complex (kind=8), Intent (inout) :: buf(:)
      Logical, Optional :: do_chk
      Integer :: BDIO_write_z64, ios

      Integer (kind=8) :: iln
      Type (BDIO_record), pointer :: p
      logical :: chk

      BDIO_write_z64 = -1
      If (fbd%imode == BDIO_R_MODE) &
           & Call BDIO_error(fbd,'BDIO_Read_z64', &
           & 'Not in write mode') 

      If (Present(do_chk)) Then
         chk = do_chk
      Else
         chk = DEFAULT_HASH_CHECK
      End If
      fbd%current => fbd%last
      fbd%rwpos = fbd%last%rend
      p => fbd%current
      If (  (p%rfmt /= BDIO_BIN_F64LE).and.&
           &(p%rfmt /= BDIO_BIN_F64BE).and.&
           &(p%rfmt /= BDIO_BIN_F64  ) ) Then
         Call BDIO_error(fbd,'BDIO_Write_z64', &
              & 'Incorrect data type') 
      End If

      If (  ( (p%rfmt == BDIO_BIN_F64BE).and.(fbd%lendian) ).or. &
           &( (p%rfmt == BDIO_BIN_F64LE).and.(.not.fbd%lendian) ) ) &
           & Then
         CALL ByteSwap(buf)
         Write(fbd%ifn,Pos=fbd%rwpos,Iostat=ios)buf
         CALL ByteSwap(buf)
      Else
         Write(fbd%ifn,Pos=fbd%rwpos,Iostat=ios)buf
      End If
      
      iln = fbd%current%rlen + 16_8*Size(buf)
      CALL Rewrite_rlen(fbd, iln)
      CALL Rewrite_hdrinfo(fbd)

      If (chk) p%hash = Hash(buf, p%hash)
      If (ios == 0) BDIO_write_z64 = Size(buf)

      Return
    End Function BDIO_write_z64
    
! ********************************
! *
    Function BDIO_write_z32(fbd,buf,do_chk)
! *
! ********************************

      Type (BDIO), Intent (inout) :: fbd
      Complex (kind=4), Intent (inout) :: buf(:)
      Logical, Optional :: do_chk
      Integer :: BDIO_write_z32, ios

      Integer (kind=8) :: iln
      Type (BDIO_record), pointer :: p
      logical :: chk

      BDIO_write_z32 = -1
      If (fbd%imode == BDIO_R_MODE) &
           & Call BDIO_error(fbd,'BDIO_Read_z32', &
           & 'Not in write mode') 

      If (Present(do_chk)) Then
         chk = do_chk
      Else
         chk = DEFAULT_HASH_CHECK
      End If
      fbd%current => fbd%last
      fbd%rwpos = fbd%last%rend
      p => fbd%current
      If (  (p%rfmt /= BDIO_BIN_F32LE).and.&
           &(p%rfmt /= BDIO_BIN_F32BE).and.&
           &(p%rfmt /= BDIO_BIN_F32  ) ) Then
         Call BDIO_error(fbd,'BDIO_Write_z32', &
              & 'Incorrect data type') 
      End If

      If (  ( (p%rfmt == BDIO_BIN_F32BE).and.(fbd%lendian) ).or. &
           &( (p%rfmt == BDIO_BIN_F32LE).and.(.not.fbd%lendian) ) ) &
           & Then
         CALL ByteSwap(buf)
         Write(fbd%ifn,Pos=fbd%rwpos,Iostat=ios)buf
         CALL ByteSwap(buf)
      Else
         Write(fbd%ifn,Pos=fbd%rwpos,Iostat=ios)buf
      End If

      iln = fbd%current%rlen + 8_8*Size(buf)
      CALL Rewrite_rlen(fbd, iln)
      CALL Rewrite_hdrinfo(fbd)

      If (do_chk) p%hash = Hash(buf, p%hash)
      If (ios == 0) BDIO_write_z32 = Size(buf)

      Return
    End Function BDIO_write_z32

! ********************************
! *
    Subroutine BDIO_seek(fbd, nrec)
! *
! ********************************

      Type (BDIO), Intent (inout) :: fbd
      Integer, Intent (in), Optional :: nrec

      Type (BDIO_record), pointer :: p

      If (Present(nrec)) Then
         p => fbd%first
         Do 
            If (p%rid == nrec) Exit
            p => p%next
         End Do
      Else
         p => fbd%current%next
      End If
      
      fbd%current => p
      fbd%rwpos = fbd%current%rpos

      Return
    End Subroutine BDIO_seek

! ********************************
! *
    Subroutine BDIO_start_header(fbd, info)
! *
! ********************************

      Type (BDIO), Intent (inout) :: fbd
      Character (len=*), Intent (in) :: info
      
      Integer (kind=4) :: i4, I, iln, iv
      Integer (kind=8) :: ipos, iend
      Type (BDIO_Record), pointer :: newr, aux

      If (isLittleEndian()) Then
         i4 = BDIO_MAGIC
         Write(fbd%ifn)i4
         fbd%lendian = .True.
      Else
         i4 = BDIO_MAGIC
         CALL Byteswap(i4)
         Write(fbd%ifn)i4
         fbd%lendian = .False.
      End If

      ! First 12 bits are the header length
      i4 = 0
      iv = 1
      CALL MVBits(iv,0,16,i4,16)
      If (.not.fbd%lendian) CALL ByteSwap(i4)
      Write(fbd%ifn)i4
      Inquire(fbd%ifn, pos=ipos)

      Allocate(newr)
      i4 = 0
      Write(fbd%ifn)i4

      Inquire(fbd%ifn,Pos=newr%hcr)
      Write(fbd%ifn)UnixTime()
      Inquire(fbd%ifn,Pos=newr%hmd)
      Write(fbd%ifn)UnixTime()

      Write(fbd%ifn)Trim(fbd%user)//char(0)
      Inquire(fbd%ifn,Pos=newr%hlu)
      Write(fbd%ifn)Trim(fbd%user)//char(0)
      newr%hlulen = Len(Trim(fbd%host))

      Write(fbd%ifn)Trim(fbd%host)//char(0)
      Inquire(fbd%ifn,Pos=newr%hlh)
      Write(fbd%ifn)Trim(fbd%host)//char(0)
      newr%hlhlen = Len(Trim(fbd%host))

      Write(fbd%ifn)Trim(info)//char(0)

      Inquire(fbd%ifn, Pos=iend)
      If (Mod(Int(iend-ipos,kind=4),4) /= 0) Then
         Do I = 1, (Int(iend-ipos,kind=4)/4+1)*4-Int(iend-ipos,kind=4)
            Write(fbd%ifn)char(0)
         End Do
         Inquire(fbd%ifn, Pos=iend)
      End If

      iln = Int(iend-ipos,kind=4)
      Read(fbd%ifn,Pos=ipos-4)i4
      If (.not.fbd%lendian) CALL ByteSwap(i4)
      CALL MVBits(iln,0,12,i4,0)
      If (.not.fbd%lendian) CALL ByteSwap(i4)
      Write(fbd%ifn,Pos=ipos-4)i4
      Read(fbd%ifn, Pos=iend)


      newr%ishdr = .True.
      newr%rlen  = Int(iln,kind=8)
      newr%rpos  = ipos
      newr%rend  = iend
      newr%rid   = fbd%tcnt
      newr%iver  = iv
      If (Associated(fbd%first)) Then
         aux => fbd%last

         aux%next => newr
         newr%prev => aux
         fbd%last => newr
      Else
         Allocate(fbd%first)
         fbd%first => newr
         fbd%last  => newr
      End If
      fbd%hcnt = fbd%hcnt + 1
      fbd%tcnt = fbd%tcnt + 1
      fbd%lasthdr => newr

      Return
    End Subroutine BDIO_start_header

! ********************************
! *
    Subroutine BDIO_start_record(fbd,ifmt,iuinfo,long)
! *
! ********************************

      Type (BDIO), Intent (inout) :: fbd
      Integer, Intent (in) :: ifmt, iuinfo
      Logical, Intent (in), Optional :: long

      Type (BDIO_record), pointer :: newr, aux
      Integer :: irc, i4, ilong
      Integer (kind=8) :: ipos, iln
      logical :: lrec

      fbd%current => fbd%last
      Read(fbd%ifn,Pos=fbd%current%rend)
      ilong = 0
      If (Present(long)) Then
         lrec = long
         if (lrec) ilong = 1
      Else
         lrec = .False.
      End If

      irc = 1
      i4  = 0
      CALL MVbits(irc,0,1,i4,0)
      CALL MVBits(ilong,0,1,i4,3)
      CALL MVBits(ifmt,0,4,i4,4)
      CALL MVBits(iuinfo,0,4,i4,8)
      Write(fbd%ifn)i4
      i4 = 0
      If (lrec) Write(fbd%ifn)i4
      Inquire(fbd%ifn,Pos=ipos)
      fbd%rwpos = ipos

      iln = 0
      Allocate(newr)
      newr%ishdr = .False.
      newr%rlen  = iln
      newr%rpos  = ipos
      newr%rend  = ipos
      newr%rfmt  = ifmt
      newr%ruinfo = iuinfo
      newr%rid   = fbd%tcnt
      newr%islong = lrec
      If (Associated(fbd%first)) Then
         aux => fbd%last

         aux%next => newr
         newr%prev => aux
         fbd%last => newr
      Else
         Allocate(fbd%first)
         fbd%first => newr
         fbd%last  => newr
      End If

      fbd%rcnt = fbd%rcnt + 1
      fbd%tcnt = fbd%tcnt + 1

      Return
    End Subroutine BDIO_start_record

! ********************************
! *
    Function BDIO_read_bin(fbd, cbuf, do_chk)
! *
! ********************************

      Type (BDIO), Intent (inout) :: fbd
      Character (len=1), Intent (inout) :: cbuf(:)
      Logical, Optional :: do_chk
      Integer :: BDIO_read_bin, ios

      Type (BDIO_record), pointer :: p
      Integer (kind=8) :: nmax, is, ie, i
      logical :: chk
      Integer :: ibf(128)

      BDIO_read_bin = -1

      If (fbd%imode == BDIO_W_MODE) &
           & Call BDIO_error(fbd,'BDIO_Read_bin', &
           & 'Not in read mode') 

      If (Present(do_chk)) Then
         chk = do_chk
      Else
         chk = .False. ! Do not checksum binary data
      End If
      p => fbd%current
      If (  (p%rfmt /= BDIO_ASC_GENERIC).and.&
           &(p%rfmt /= BDIO_ASC_XML).and.&
           &(p%rfmt /= BDIO_BIN_GENERIC).and.&
           &(p%rfmt /= BDIO_ASC_EXEC  ) ) Then
         Call BDIO_error(fbd,'BDIO_Read_bin', &
              & 'Incorrect data type') 
      End If

      nmax = size(cbuf)
      If (size(cbuf) > (p%rend-fbd%rwpos)) nmax = (p%rend-fbd%rwpos)
      If (nmax .le. 0) Return
      Read(fbd%ifn,Pos=fbd%rwpos,iostat=ios)cbuf(:nmax)
      
      If (chk) Then
         If (mod(nmax,4_8) /= 0) Call BDIO_error(fbd,'BDIO_Write_bin', &
              & 'Binary data needs be multiple of 4bytes to checksum') 
         I = 0
         Do
            is = 1+512*I
            ie = is+512
            If (ie > nmax) ie=nmax 
            ibf = Transfer(cbuf(is:ie), ibf)
            p%hash = Hash(ibf(:(ie-is)/4), p%hash)
            If (ie == nmax) Exit
            I = I+1
         End Do
      End If

      fbd%rwpos = fbd%rwpos + nmax
      If (ios == 0) BDIO_read_bin = Int(nmax,kind=4)
      
      Return
    End Function BDIO_read_bin

! ********************************
! *
    Function BDIO_read_i32(fbd, ibuf, do_chk)
! *
! ********************************

      Type (BDIO), Intent (inout) :: fbd
      Integer, Intent (inout) :: ibuf(:)
      Logical, Optional :: do_chk
      Integer :: BDIO_read_i32, ios

      Type (BDIO_record), pointer :: p
      Integer (kind=8) :: nmax
      logical :: chk

      BDIO_read_i32 = -1

      If (fbd%imode == BDIO_W_MODE) &
           & Call BDIO_error(fbd,'BDIO_Read_i32', &
           & 'Not in read mode') 

      If (Present(do_chk)) Then
         chk = do_chk
      Else
         chk = DEFAULT_HASH_CHECK
      End If
      p => fbd%current
      If (  (p%rfmt /= BDIO_BIN_INT32LE).and.&
           &(p%rfmt /= BDIO_BIN_INT32BE).and.&
           &(p%rfmt /= BDIO_BIN_INT32  ) ) Then
         Call BDIO_error(fbd,'BDIO_Read_i32', &
              & 'Incorrect data type') 
      End If

      nmax = size(ibuf)
      If (4_8*size(ibuf) > (p%rend-fbd%rwpos)) nmax = (p%rend-fbd%rwpos)/4
      If (nmax .le. 0) Return
      Read(fbd%ifn,Pos=fbd%rwpos,iostat=ios)ibuf(:nmax)
      If (  ( (p%rfmt == BDIO_BIN_INT32BE).and.(fbd%lendian) ).or. &
           &( (p%rfmt == BDIO_BIN_INT32LE).and.(.not.fbd%lendian) ) ) &
           & CALL ByteSwap(ibuf)

      
      If (chk) p%hash = Hash(ibuf(:nmax), p%hash)
      fbd%rwpos = fbd%rwpos + 4*nmax

      If (ios == 0) BDIO_read_i32 = Int(nmax,kind=4)
      
      Return
    End Function BDIO_read_i32

! ********************************
! *
    Function BDIO_read_i64(fbd, ibuf, do_chk)
! *
! ********************************

      Type (BDIO), Intent (inout) :: fbd
      Integer (kind=8), Intent (inout) :: ibuf(:)
      Logical, Optional :: do_chk
      Integer :: BDIO_read_i64, ios

      Type (BDIO_record), pointer :: p
      Integer (kind=8) :: nmax
      logical :: chk

      BDIO_read_i64 = -1
      If (fbd%imode == BDIO_W_MODE) &
           & Call BDIO_error(fbd,'BDIO_Read_i64', &
           & 'Not in read mode') 

      If (Present(do_chk)) Then
         chk = do_chk
      Else
         chk = DEFAULT_HASH_CHECK
      End If
      p => fbd%current
      If (  (p%rfmt /= BDIO_BIN_INT64LE).and.&
           &(p%rfmt /= BDIO_BIN_INT64BE).and.&
           &(p%rfmt /= BDIO_BIN_INT64  ) ) Then
         Call BDIO_error(fbd,'BDIO_Read_i64', &
              & 'Incorrect data type') 
      End If

      nmax = size(ibuf)
      If (8_8*size(ibuf) > (p%rend-fbd%rwpos)) nmax = (p%rend-fbd%rwpos)/8
      If (nmax .le. 0) Return
      Read(fbd%ifn,Pos=fbd%rwpos,iostat=ios)ibuf(:nmax)
      If (  ( (p%rfmt == BDIO_BIN_INT64BE).and.(fbd%lendian) ).or. &
           &( (p%rfmt == BDIO_BIN_INT64LE).and.(.not.fbd%lendian) ) ) &
           & CALL ByteSwap(ibuf)
      
      If (chk) p%hash = Hash(ibuf(:nmax), p%hash)
      fbd%rwpos = fbd%rwpos + 8*nmax

      If (ios == 0) BDIO_read_i64 = Int(nmax,kind=4)
      
      Return
    End Function BDIO_read_i64

! ********************************
! *
    Function BDIO_read_f32(fbd, buf, do_chk)
! *
! ********************************

      Type (BDIO), Intent (inout) :: fbd
      Real (kind=4), Intent (inout) :: buf(:)
      Logical, Optional :: do_chk
      Integer :: BDIO_read_f32, ios

      Type (BDIO_record), pointer :: p
      Integer (kind=8) :: nmax
      logical :: chk

      BDIO_read_f32 = -1
      If (fbd%imode == BDIO_W_MODE) &
           & Call BDIO_error(fbd,'BDIO_Read_f32', &
           & 'Not in read mode') 

      If (Present(do_chk)) Then
         chk = do_chk
      Else
         chk = DEFAULT_HASH_CHECK
      End If
      p => fbd%current
      If (  (p%rfmt /= BDIO_BIN_F32LE).and.&
           &(p%rfmt /= BDIO_BIN_F32BE).and.&
           &(p%rfmt /= BDIO_BIN_F32  ) ) Then
         Call BDIO_error(fbd,'BDIO_Read_f32', &
              & 'Incorrect data type') 
      End If

      nmax = size(buf)
      If (4_8*size(buf) > (p%rend-fbd%rwpos)) nmax = (p%rend-fbd%rwpos)/4
      If (nmax .le. 0) Return
      Read(fbd%ifn,Pos=fbd%rwpos,iostat=ios)buf(:nmax)
      If (  ( (p%rfmt == BDIO_BIN_F32BE).and.(fbd%lendian) ).or. &
           &( (p%rfmt == BDIO_BIN_F32LE).and.(.not.fbd%lendian) ) ) &
           & CALL ByteSwap(buf)

      
      If (chk) p%hash = Hash(buf(:nmax), p%hash)
      fbd%rwpos = fbd%rwpos + 4*nmax

      If (ios == 0) BDIO_read_f32 = Int(nmax,kind=4)
      
      Return
    End Function BDIO_read_f32

! ********************************
! *
    Function BDIO_read_f64(fbd, buf, do_chk)
! *
! ********************************

      Type (BDIO), Intent (inout) :: fbd
      Real (kind=8), Intent (inout) :: buf(:)
      Logical, Optional :: do_chk
      Integer :: BDIO_read_f64, ios

      Type (BDIO_record), pointer :: p
      Integer (kind=8) :: nmax
      logical :: chk

      BDIO_read_f64 = -1
      If (fbd%imode == BDIO_W_MODE) &
           & Call BDIO_error(fbd,'BDIO_Read_f64', &
           & 'Not in read mode') 

      If (Present(do_chk)) Then
         chk = do_chk
      Else
         chk = DEFAULT_HASH_CHECK
      End If
      p => fbd%current
      If (  (p%rfmt /= BDIO_BIN_F64LE).and.&
           &(p%rfmt /= BDIO_BIN_F64BE).and.&
           &(p%rfmt /= BDIO_BIN_F64  ) ) Then
         Call BDIO_error(fbd,'BDIO_Read_f64', &
              & 'Incorrect data type') 
      End If

      nmax = size(buf)
      If (8_8*size(buf) > (p%rend-fbd%rwpos)) nmax = (p%rend-fbd%rwpos)/8
      If (nmax .le. 0) Return
      Read(fbd%ifn,Pos=fbd%rwpos,iostat=ios)buf(:nmax)
      If (  ( (p%rfmt == BDIO_BIN_F64BE).and.(fbd%lendian) ).or. &
           &( (p%rfmt == BDIO_BIN_F64LE).and.(.not.fbd%lendian) ) ) &
           & CALL ByteSwap(buf)
      
      If (do_chk) p%hash = Hash(buf(:nmax), p%hash)
      fbd%rwpos = fbd%rwpos + 8*nmax

      If (ios == 0) BDIO_read_f64 = Int(nmax,kind=4)
      
      Return
    End Function BDIO_read_f64

! ********************************
! *
    Function BDIO_read_z32(fbd, buf, do_chk)
! *
! ********************************

      Type (BDIO), Intent (inout) :: fbd
      Complex (kind=4), Intent (inout) :: buf(:)
      Logical, Optional :: do_chk
      Integer :: BDIO_read_z32, ios

      Type (BDIO_record), pointer :: p
      Integer (kind=8) :: nmax
      logical :: chk

      BDIO_read_z32 = -1
      If (fbd%imode == BDIO_W_MODE) &
           & Call BDIO_error(fbd,'BDIO_Read_z32', &
           & 'Not in read mode') 

      If (Present(do_chk)) Then
         chk = do_chk
      Else
         chk = DEFAULT_HASH_CHECK
      End If
      p => fbd%current
      If (  (p%rfmt /= BDIO_BIN_F32LE).and.&
           &(p%rfmt /= BDIO_BIN_F32BE).and.&
           &(p%rfmt /= BDIO_BIN_F32  ) ) Then
         Call BDIO_error(fbd,'BDIO_Read_z32', &
              & 'Incorrect data type') 
      End If

      nmax = size(buf)
      If (8_8*size(buf) > (p%rend-fbd%rwpos)) nmax = (p%rend-fbd%rwpos)/8
      If (nmax .le. 0) Return
      Read(fbd%ifn,Pos=fbd%rwpos,iostat=ios)buf(:nmax)
      If (  ( (p%rfmt == BDIO_BIN_F32BE).and.(fbd%lendian) ).or. &
           &( (p%rfmt == BDIO_BIN_F32LE).and.(.not.fbd%lendian) ) ) &
           & CALL ByteSwap(buf)

      
      If (do_chk) p%hash = Hash(buf(:nmax), p%hash)
      fbd%rwpos = fbd%rwpos + 8*nmax

      If (ios == 0) BDIO_read_z32 = Int(nmax,kind=4)
      
      Return
    End Function BDIO_read_z32

! ********************************
! *
    Function BDIO_read_z64(fbd, buf, do_chk)
! *
! ********************************

      Type (BDIO), Intent (inout) :: fbd
      Complex (kind=8), Intent (inout) :: buf(:)
      Logical, Optional :: do_chk
      Integer :: BDIO_read_z64, ios

      Type (BDIO_record), pointer :: p
      Integer (kind=8) :: nmax
      logical :: chk

      BDIO_read_z64 = -1
      If (fbd%imode == BDIO_W_MODE) &
           & Call BDIO_error(fbd,'BDIO_Read_z64', &
           & 'Not in read mode') 

      If (Present(do_chk)) Then
         chk = do_chk
      Else
         chk = DEFAULT_HASH_CHECK
      End If
      p => fbd%current
      If (  (p%rfmt /= BDIO_BIN_F64LE).and.&
           &(p%rfmt /= BDIO_BIN_F64BE).and.&
           &(p%rfmt /= BDIO_BIN_F64  ) ) Then
         Call BDIO_error(fbd,'BDIO_Read_z64', &
              & 'Incorrect data type') 
      End If

      nmax = size(buf)
      If (16_8*size(buf) > (p%rend-fbd%rwpos)) nmax = (p%rend-fbd%rwpos)/16
      If (nmax .le. 0) Return
      Read(fbd%ifn,Pos=fbd%rwpos,iostat=ios)buf(:nmax)
      If (  ( (p%rfmt == BDIO_BIN_F64BE).and.(fbd%lendian) ).or. &
           &( (p%rfmt == BDIO_BIN_F64LE).and.(.not.fbd%lendian) ) ) &
           & CALL ByteSwap(buf)
      
      If (chk) p%hash = Hash(buf(:nmax), p%hash)
      fbd%rwpos = fbd%rwpos + 16*nmax

      If (ios == 0) BDIO_read_z64 = Int(nmax,kind=4)
      
      Return
    End Function BDIO_read_z64
    
! ********************************
! *
    Function BDIO_open(fname, mode, protocol_info) Result (fbd)
! *
! ********************************
      Character (len=*), Intent (in) :: fname
      Character (len=1), Intent (in) :: mode
      Character (len=*), Intent (in), Optional ::  protocol_info
      Integer (kind=8) :: ipos
      
      Type (BDIO) :: fbd

      Logical :: is_used

      If (fbd%opened) Call BDIO_error(fbd,'BDIO_Open', &
              & 'BDIO already in use') 

      Select Case (mode)
      Case ('r')
         fbd%imode = BDIO_R_MODE
      Case ('w')
         fbd%imode = BDIO_W_MODE
      Case ('a')
         fbd%imode = BDIO_A_MODE
      Case Default
         Call BDIO_error(fbd,'BDIO_Open', &
              & 'Incorrect mode') 
      End Select
      
      fbd%lendian = isLittleEndian()
      fbd%ifn = 69
      Do 
         Inquire(fbd%ifn, Opened=is_used)
         If (is_used) Then
            fbd%ifn = fbd%ifn + 1
         Else
            Exit
         End If
      End Do

      Select Case (fbd%imode)
      Case (BDIO_R_MODE) 
         Open (File=Trim(fname), unit=fbd%ifn, ACTION="READ", &
              & Form='UNFORMATTED', Access='STREAM')
         Inquire(fbd%ifn, Pos=ipos)

         fbd%opened = .True.
         CALL BDIO_parse(fbd)
         fbd%current => fbd%first
      CASE (BDIO_A_MODE) 
         Open (File=Trim(fname), unit=fbd%ifn, ACTION="READWRITE", &
              & Form='UNFORMATTED', Access='STREAM')
         Rewind(fbd%ifn)

         fbd%opened = .True.
         CALL BDIO_parse(fbd)
         fbd%current => fbd%last
      CASE (BDIO_W_MODE)
         Open (File=Trim(fname), unit=fbd%ifn, ACTION="READWRITE", &
              & Form='UNFORMATTED', Access='STREAM', STATUS='NEW')

         fbd%opened=.True.
         CALL BDIO_start_header(fbd,protocol_info)
         fbd%current => fbd%first
      End Select

      Return
    End Function BDIO_open

! ********************************
! *
    Subroutine BDIO_parse(fbd)
! *
! ********************************

      Type (BDIO), Intent (inout) :: fbd

      Integer (kind=4) :: i4, irc
      Integer (kind=8) :: ipos
      Character (len=32) :: ai
      
      Rewind(fbd%ifn)
      Do 
         Inquire(fbd%ifn, Pos=ipos)
         Read(fbd%ifn,END=20)i4
         irc = 0
         CALL MVbits(i4,0,1,irc,0)

         If (i4==BDIO_MAGIC) Then
            Read(fbd%ifn, Pos=ipos)
            CALL BDIO_Read_header(fbd)
         Else if (irc == 1) Then
            Read(fbd%ifn, Pos=ipos)
            CALL BDIO_Read_record(fbd)
         Else
            Write(ai,'(1I32)')ipos
            CALL BDIO_error(fbd, 'BDIO_parse', 'Neither a record nor a header at position: '//Trim(ai))
         End If
      End Do
         
20    Continue

      Return
    End Subroutine BDIO_parse

! ********************************
! *
    Subroutine BDIO_read_record(fbd)
! *
! ********************************

      Type (BDIO), Intent (inout) :: fbd

      Integer (kind=4) :: i4, ilong, irc, j, ifmt, iuinfo
      Integer (kind=8) :: ipos, iend, iln
      Integer (kind=8) :: jlong

      Type (BDIO_Record), pointer :: newr, aux

      ! Record
      Read(fbd%ifn,END=20)i4
      irc = 0
      ilong = 0
      ifmt = 0
      iuinfo = 0
      CALL MVbits(i4,0,1,irc,0)
      CALL MVbits(i4,3,1,ilong,0)
      CALL MVbits(i4,4,4,ifmt,0)
      CALL MVbits(i4,8,4,iuinfo,0)
      
      j = 0
      CALL MVbits(i4,12,20,j,0)
      iln = Int(j,kind=8)
      If (ilong==1) Then
         Read(fbd%ifn)i4
         CALL MVBits(i4,0,32,j,0)
         jlong=Int(j,kind=8)
         CALL MVBits(jlong,0,32,iln,20)
         iln = iln - 4
      End If
      Inquire(fbd%ifn, Pos=ipos)
      Read(fbd%ifn, Pos=ipos+iln)
      Inquire(fbd%ifn, Pos=iend)
      
      Allocate(newr)
      newr%ishdr = .False.
      newr%rlen  = iln
      newr%rpos  = ipos
      newr%rend  = iend
      newr%rfmt  = ifmt
      newr%ruinfo = iuinfo
      newr%rid   = fbd%tcnt
      newr%islong = .False. 
      If (ilong==1) Then
         newr%islong = .True. 
      End If
      
      If (Associated(fbd%first)) Then
         aux => fbd%last

         aux%next => newr
         newr%prev => aux
         fbd%last => newr
      Else
         Allocate(fbd%first)
         fbd%first => newr
         fbd%last  => newr
      End If
      fbd%rcnt = fbd%rcnt + 1
      fbd%tcnt = fbd%tcnt + 1
         
20    Continue

      Return
    End Subroutine BDIO_read_record

! ********************************
! *
    Subroutine BDIO_read_header(ptf)
! *
! ********************************

      Type (BDIO), Intent (inout) :: ptf

      Integer (kind=4) :: i4, isp, iv, iln
      Character (kind=1) :: ch
      Integer (kind=8) :: ipos, iend

      Type (BDIO_Record), pointer :: newr, aux
      Integer :: I

      Read(ptf%ifn,END=20)i4
      if (.not.ptf%lendian) CALL ByteSwap(i4)
      If (i4/=BDIO_MAGIC) Then
         Write(0,*)'File not recognized as BDIO'
         Stop
      End If

      Read(ptf%ifn)i4
      if (.not.ptf%lendian) CALL ByteSwap(i4)

      iln = 0
      isp = 0
      iv  = 0
      CALL MVbits(i4,0,12,iln,0)
      CALL MVbits(i4,12,4,isp,0)
      CALL MVbits(i4,16,16,iv,0)
      Inquire(ptf%ifn, pos=ipos)
      Read(ptf%ifn,Pos=ipos+iln)
      Inquire(ptf%ifn, pos=iend)
      
      Allocate(newr)
      newr%ishdr = .True.
      newr%rlen  = Int(iln,kind=8)
      newr%rpos  = ipos
      newr%rend  = iend
      newr%rid   = ptf%tcnt
      newr%iver  = iv

      Read(ptf%ifn,Pos=ipos)
      If (iln>0) Then
         Read(ptf%ifn)i4
         Inquire(ptf%ifn,Pos=newr%hcr)
         Read(ptf%ifn)newr%created
         Inquire(ptf%ifn,Pos=newr%hmd)
         Read(ptf%ifn)newr%modified
         I=1
         Do
            Read(ptf%ifn)ch
            If (ch == char(0)) Exit
            newr%cuser(I:I) = ch
            I=I+1
         End Do
!         Write(*,*)'cuser: ', I, Trim(newr%cuser)
         I=1
         Do
            Inquire(ptf%ifn,Pos=newr%hlu)
            Read(ptf%ifn)ch
            If (ch == char(0)) Exit
            newr%luser(I:I) = ch
            I=I+1
         End Do
         newr%hlulen=I
!         Write(*,*)'luser: ', I, Trim(newr%luser)
         I=1
         Do
            Read(ptf%ifn)ch
            If (ch == char(0)) Exit
            newr%chost(I:I) = ch
            I=I+1
         End Do
!         Write(*,*)'chost: ', I, Trim(newr%chost)
         I=1
         Do
            Inquire(ptf%ifn,Pos=newr%hlh)
            Read(ptf%ifn)ch
            If (ch == char(0)) Exit
            newr%lhost(I:I) = ch
            I=I+1
         End Do
         newr%hlhlen=I
!         Write(*,*)'lhost: ', I, Trim(newr%lhost)
         I=1
         Do
            Read(ptf%ifn)ch
            If (ch == char(0)) Exit
            newr%info(I:I) = ch
            I=I+1
         End Do
!         Write(*,*)'info: ', I, Trim(newr%info)
      End If
      Read(ptf%ifn,Pos=iend)
      
      If (Associated(ptf%first)) Then
         aux => ptf%last

         aux%next => newr
         newr%prev => aux
         ptf%last => newr
      Else
         Allocate(ptf%first)
         ptf%first => newr
         ptf%last  => newr
      End If
      ptf%hcnt = ptf%hcnt + 1
      ptf%tcnt = ptf%tcnt + 1
      ptf%lasthdr => newr

20    Continue

      Return
    End Subroutine BDIO_read_header

! ********************************
! *
    Subroutine BDIO_show_header(p)
! *
! ********************************
      
      Type (BDIO_record), pointer :: p
      
      Write(*,'(1I4,3X,1A,3X,1I4,1I10,1I4,1A15,1L4)')&
           & p%rid, 'header',p%iver, p%rlen, p%ruinfo, '', p%islong  

      Return
    End Subroutine BDIO_show_header

! ********************************
! *
    Subroutine BDIO_show_record(p)
! *
! ********************************
      
      Type (BDIO_record), pointer :: p
      
      Write(*,'(1I4,3X,1A,3X,1I4,1I10,1I6,1A15,1L4)')&
           & p%rid, 'record', p%rfmt, p%rlen, p%ruinfo, '', p%islong  

      Return
    End Subroutine BDIO_show_record

! ********************************
! *
    Subroutine BDIO_show(ptf)
! *
! ********************************

      Type (BDIO), Intent (in) :: ptf
      Type (BDIO_record), pointer :: p
      
      Write(*,'(1A,5X,1A,5X,1A,5X,1A,3X,1A,2X,1A)')'ID','record', 'type', 'size', 'uID', 'starts with', 'long' 

      p => ptf%first
      Do 
         If (.not.Associated(p)) Exit
         If (p%ishdr) Then
            CALL BDIO_show_header(p)
         Else
            CALL BDIO_show_record(p)
         End If
         p => p%next
      End Do

      Return
    End Subroutine BDIO_show

! ********************************
! *
    Subroutine Rewrite_hdrinfo(fbd)
! *
! ********************************

      Type (BDIO), Intent (inout) :: fbd

      Integer (kind=8) :: actual
      Type (BDIO_record), pointer :: ph

      Inquire(fbd%ifn,Pos=actual)
      ph => fbd%lasthdr
      Write(fbd%ifn,Pos=ph%hmd)UnixTime()

      Read(fbd%ifn,Pos=actual)

      Return
    End Subroutine Rewrite_hdrinfo

! ********************************
! *
    Subroutine Rewrite_rlen(fbd, iln)
! *
! ********************************
      
      Type (BDIO), Intent (inout) :: fbd
      Integer (kind=8), Intent (in) :: iln
      
      Integer (kind=4) :: i4(2), j
      Integer (kind=8) :: jl
      Type (BDIO_record), pointer :: p

      i4 = 0
      p => fbd%current
      If (p%islong) Then
         Read(fbd%ifn,Pos=p%rpos-8)i4(1:2)
         CALL MVBits(iln+4, 0, 20, jl, 0)
         j = Int(jl,kind=4)
         CALL MVBits(j,0,20,i4(1),12)
         jl = 0
         CALL MVBits(iln+4, 20, 32, jl, 0)
         j = Int(jl,kind=4)
         CALL MVBits(j,0,32,i4(2),0)
         Write(fbd%ifn,Pos=p%rpos-8)i4(1:2)
      Else
         Read(fbd%ifn,Pos=p%rpos-4)i4(1)
         CALL MVBits(iln, 0, 20, jl, 0)
         j = Int(jl,kind=4)
         CALL MVBits(j,0,20,i4(1),12)
         Write(fbd%ifn,Pos=fbd%current%rpos-4)i4(1)
      End If

      p%rlen = iln
      p%rend = fbd%current%rpos + iln

      Return
    End Subroutine Rewrite_rlen

! ********************************         
! *  
    Function isLittleEndian()
! * 
! ********************************    

      Logical :: isLittleEndian
      Character (kind=1) :: ch(4)
      Integer (kind=4) :: I(1), Isw

      I   = 0
      Isw = 0
      ch = Transfer(I, ch)
      ch(1) = achar(48)
      I   = Transfer(ch, I)

      Isw = 48
      CALL ByteSwap(Isw)

      isLittleEndian = .True.
      If (I(1) == 48) Then
         Return
      Else If (I(1) == Isw) Then
         isLittleEndian = .False.
         Return
      Else
         Write(0,*)'What a mess of Endianness!'
      End If

      Return
    End Function isLittleEndian

! ********************************
! *
    Subroutine byteswap_int32(Iii)
! *
! ********************************

      Integer (kind=4), Intent (inout) :: Iii
      
      Character (kind=1) :: isw(4)
      Integer (kind=4) :: J(1)

      isw  = Transfer(Iii,isw, 4)
      J    = Transfer(isw(4:1:-1), J)
      Iii  = J(1)

      Return
    End Subroutine byteswap_int32

! ********************************
! *
    Subroutine byteswap_int32V(Iii)
! *
! ********************************

      Integer (kind=4), Intent (inout) :: Iii(:)
      
      Character (kind=1) :: isw(4)
      Integer (kind=4) :: J(1), K

      Do K = 1, Size(Iii)
         isw  = Transfer(Iii(K),isw, 4)
         J    = Transfer(isw(4:1:-1), J)
         Iii(K)  = J(1)
      End Do

      Return
    End Subroutine byteswap_int32V

! ********************************
! *
    Subroutine byteswap_int64(Iii)
! *
! ********************************

      Integer (kind=8), Intent (inout) :: Iii
      
      Character (kind=1) :: isw(8)
      Integer (kind=8) :: J(1)

      isw  = Transfer(Iii,isw, 8)
      J    = Transfer(isw(8:1:-1), J)
      Iii  = J(1)

      Return
    End Subroutine byteswap_int64

! ********************************
! *
    Subroutine byteswap_int64V(Iii)
! *
! ********************************

      Integer (kind=8), Intent (inout) :: Iii(:)
      
      Character (kind=1) :: isw(8)
      Integer (kind=8) :: J(1)
      Integer :: K

      Do K = 1, Size(Iii)
         isw  = Transfer(Iii(K),isw, 8)
         J    = Transfer(isw(8:1:-1), J)
         Iii(K)  = J(1)
      End Do

      Return
    End Subroutine byteswap_int64V

! ********************************
! *
    Subroutine byteswap_R(d)
! *
! ********************************

      Real (kind=4), Intent (inout) :: d
      
      Character (kind=1) :: isw(4)
      Real (kind=4) :: dd(1)

      isw  = Transfer(d,isw, 4)
      dd   = Transfer(isw(4:1:-1), dd)
      d  = dd(1)

      Return
    End Subroutine byteswap_R

! ********************************
! *
    Subroutine byteswap_RV(d)
! *
! ********************************

      Real (kind=4), Intent (inout) :: d(:)
      
      Character (kind=1) :: isw(4)
      Real (kind=4) :: dd(1)
      Integer :: I

      Do I = 1, Size(d)
         isw  = Transfer(d(I),isw, 4)
         dd   = Transfer(isw(4:1:-1), dd)
         d(I) = dd(1)
      End Do

      Return
    End Subroutine byteswap_RV

! ********************************
! *
    Subroutine byteswap_D(d)
! *
! ********************************

      Real (kind=8), Intent (inout) :: d
      
      Character (kind=1) :: isw(8)
      Real (kind=8) :: dd(1)

      isw  = Transfer(d,isw, 8)
      dd   = Transfer(isw(8:1:-1), dd)
      d  = dd(1)

      Return
    End Subroutine byteswap_D

! ********************************
! *
    Subroutine byteswap_DV(d)
! *
! ********************************

      Real (kind=8), Intent (inout) :: d(:)
      
      Character (kind=1) :: isw(8)
      Real (kind=8) :: dd(1)
      Integer :: I

      Do I = 1, Size(d)
         isw  = Transfer(d(I),isw, 8)
         dd   = Transfer(isw(8:1:-1), dd)
         d(I) = dd(1)
      End Do

      Return
    End Subroutine byteswap_DV

! ********************************
! *
    Subroutine byteswap_Z(z)
! *
! ********************************

      Complex (kind=4), Intent (inout) :: z
      
      Real (kind=4) :: d(2)

      d = Transfer(z,d)
      CALL ByteSwap(d)
      z = Transfer(d, z)

      Return
    End Subroutine byteswap_Z

! ********************************
! *
    Subroutine byteswap_DZ(z)
! *
! ********************************

      Complex (kind=8), Intent (inout) :: z
      
      Real (kind=8) :: d(2)

      d = Transfer(z,d)
      CALL ByteSwap(d)
      z = Transfer(d, z)

      Return
    End Subroutine byteswap_DZ

! ********************************
! *
    Subroutine byteswap_DZV(z)
! *
! ********************************

      Complex (kind=8), Intent (inout) :: z(:)
      
      Real (kind=8) :: d(2)
      Integer :: I

      Do I = 1, Size(z)
         d = Transfer(z(I),d)
         CALL ByteSwap(d)
         z(I) = Transfer(d, z(I))
      End Do

      Return
    End Subroutine byteswap_DZV

! ********************************
! *
    Subroutine byteswap_ZV(z)
! *
! ********************************

      Complex (kind=4), Intent (inout) :: z(:)
      
      Real (kind=4) :: d(2)
      Integer :: I

      Do I = 1, Size(z)
         d = Transfer(z(I),d)
         CALL ByteSwap(d)
         z(I) = Transfer(d, z(I))
      End Do

      Return
    End Subroutine byteswap_ZV

! ********************************
! *
    Subroutine BDIO_setuser(fbd, suser)
! *
! ********************************
      
      Type (BDIO), Intent (inout) :: fbd
      Character (len=*), Intent (in) :: suser
      Integer :: I

      fbd%user = ''
      Do I = 1, Min(len(Trim(suser)),BDIO_SHORT_LEN-1)
         fbd%user(I:I) = suser(I:I)
      End Do
      fbd%user(I:I) = achar(0)

      Return
    End Subroutine BDIO_setuser

! ********************************
! *
    Subroutine BDIO_sethost(fbd,shost)
! *
! ********************************
      
      Type (BDIO), Intent (inout) :: fbd
      Character (len=*), Intent (in) :: shost
      Integer :: I

      fbd%host = ''
      Do I = 1, Min(len(Trim(shost)),BDIO_SHORT_LEN-1)
         fbd%host(I:I) = shost(I:I)
      End Do
      fbd%host(I:I) = achar(0)

      Return
    End Subroutine BDIO_sethost

! ********************************
! *
    Subroutine BDIO_sethashing(ok)
! *
! ********************************
      
      Logical, Intent (in) :: ok
      
      DEFAULT_HASH_CHECK = ok

      Return
    End Subroutine BDIO_sethashing


!!$! ********************************
!!$! *
!!$    Subroutine unix2date(utime, asctime)
!!$! *
!!$! ********************************
!!$
!!$      Integer, Intent (in) ::  utime
!!$      Character (len=24), Intent (out) :: asctime
!!$      Integer :: idate(6)
!!$      
!!$      !*utime  input  Unix system time, seconds since 1970.0
!!$      !*idate  output Array: 1=year, 2=month, 3=date, 4=hour, 5=minute, 6=secs
!!$      !*-Author  Clive Page, Leicester University, UK.   1995-MAY-2
!!$      Integer :: mjday, nsecs
!!$      Real (kind=4) :: day
!!$      
!!$      !*Note the MJD algorithm only works from years 1901 to 2099.
!!$      
!!$      mjday    = int(utime/86400 + 40587)
!!$      idate(1) = 1858 + int( (mjday + 321.51) / 365.25)
!!$      day      = aint( mod(mjday + 262.25, 365.25) ) + 0.5
!!$      idate(2) = 1 + int(mod(day / 30.6 + 2.0, 12.0) )
!!$      idate(3) = 1 + int(mod(day,30.6))
!!$      nsecs    = mod(utime, 86400)
!!$      idate(6) = mod(nsecs, 60)
!!$      nsecs    = nsecs / 60
!!$      idate(5) = mod(nsecs, 60)
!!$      idate(4) = nsecs / 60
!!$
!!$      Write(asctime,10)NAMES_OF_DAYS(t%wday), ' ', &
!!$           & NAMES_OF_MONTHS(idate(2)), ' ', t%mday,' ', &
!!$           & t%hour, ':', t%min, ':', t%sec, ' ', idate(1)
!!$
!!$10  FORMAT((4A,1I2,1A,1I2,1A1,1I2.2,1A1,1I2.2,1A1,1I4))
!!$
!!$      Return
!!$    End Subroutine unix2date

Function UnixTime()

  Integer :: UnixTime

  Character (len=8)  :: Datestr
  Character (len=10) :: Timestr

  Character (len=1) :: ch
  Integer :: year,mon,mday,hour,min,sec,msec
  Integer, Parameter :: monadd(12) = &
       & (/0,31,59,90,120,151,181,212,242,273,303,334/)

  
  CALL Date_and_Time(Datestr, Timestr)
  
  Read(Datestr,'(1I4,1I2,1I2)')year, mon, mday
  Read(Timestr,'(1I2,1I2,1I2,1A1,1I3)')hour, min, sec, &
       & ch, msec
    
  year = year - 1970
  mday = mday + monadd(mon) - 1
  hour = hour-2
  UnixTime = ((((year * 365 + year/4 - year/100 + year/400 &
       & + mday)) * 24 + hour) * 60 + min) * 60 + sec 

  Return
End Function UnixTime


End MODULE ModBDio