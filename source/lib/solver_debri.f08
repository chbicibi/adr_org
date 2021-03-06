module Solver_Debri
  use Base_Func
  use Solver_Orbit

  implicit none

  private
  public :: Debri
  public :: FILEPATH_DEBRI, FILEPATH_RCS
  public :: NUM_OBJECT_ALL, DEBRIS
  public :: ReadDebri, MJD

  type :: Debri
    type(TOrbit) :: orbit
    integer      :: revol_num = 0
    real(8)      :: rcs       = 0d0
  end type Debri

  integer :: NUM_OBJECT_ALL
  character(:), allocatable :: FILEPATH_DEBRI
  character(:), allocatable :: FILEPATH_RCS
  type(Debri), allocatable :: DEBRIS(:)

  contains

  ! ----------------------------------------------------------------------------
  ! Initialize
  ! ----------------------------------------------------------------------------
  subroutine ReadDebri
    character(69) :: line1, line2
    type(TOrbit)  :: orbit
    real(8)       :: day, inc, ran, ecc, ap, ma, mm
    integer       :: year, unit, i, j

    ALLOCATE(DEBRIS(0:NUM_OBJECT_ALL))

    open(newunit=unit, file=FILEPATH_DEBRI)
      do i = 1, NUM_OBJECT_ALL
        read(unit, *)
        read(unit, "(a)") line1
        read(unit, "(a)") line2

        read(line1(19:20), *) year
        read(line1(21:32), *) day

        read(line2( 9:16), *) inc
        read(line2(18:25), *) ran
        line2(25:26) = "0."
        read(line2(25:33), *) ecc
        read(line2(35:42), *) ap
        read(line2(44:51), *) ma
        read(line2(53:63), *) mm
        read(line2(64:68), *) DEBRIS(i)%revol_num

        if (year < 57) then
          year = year + 2000
        else
          year = year + 1900
        end if
        DEBRIS(i)%orbit = GetOrbit(MJD(year, day), inc, ran, ecc, ap, ma, mm)
        call DEBRIS(i)%orbit%Move(MJD(2017, 0d0), 0)
      end do
    close(unit)

    open(newunit=unit, file=FILEPATH_RCS)
      print *, unit
      do i = 1, NUM_OBJECT_ALL
        read(unit, *) DEBRIS(i)%rcs
      end do
    close(unit)
  end subroutine ReadDebri

  subroutine Transfer(debri_num, date_s, args, del_v, del_t)
    integer,        intent(in)  :: debri_num(2)
    real(8),        intent(in)  :: date_s, args(6)
    real(8),        intent(out) :: del_v, del_t
    type(TOrbit)                :: orbit1, orbit2, orbit_d, orbit_t, orbit_a, orbit1_a, orbit2_a
    real(8)                     :: rho, dnu, t(3), n(3), date, date_d, date_a, theta, axis(3), axis_t(3), offset
    real(8)                     :: sma_t, tof, pos_d(3), pos_a(3), vel_d(3), vel_t(3), vel_a(3), v1(3), v2(3)
    integer                     :: i

    rho    = args(1)
    dnu    = args(2)
    t      = [args(3:4), 1d0]
    n      = [args(5:6), 0d0]

    del_v  = 0d0
    del_t  = 0d0

    if (debri_num(1) == debri_num(2)) return

    date     = date_s
    orbit1   = DEBRIS(debri_num(1))%orbit%CalcOrbit(date)
    orbit2   = DEBRIS(debri_num(2))%orbit%CalcOrbit(date)

    do i = 1, 3
      axis    = Unit(Cross(orbit1%axis_w, orbit2%axis_w)) * (-1) ** (i - 1)
      theta   = Sgn(dot_product(Cross(orbit1%axis_w, orbit2%axis_w), axis)) * Angle(orbit1%axis_w, orbit2%axis_w)

      offset  = modulo(TAtoMA(Angle(orbit1%axis_p, axis, orbit1%axis_w), orbit1%ecc) - orbit1%ma, PI2) / orbit1%mm

      date_d  = date + offset / 86400d0
      orbit_d = orbit1%CalcOrbit(date_d)
      pos_d   = orbit_d%GetPosition()
      vel_d   = orbit_d%GetVelocity()

      select case (i)
      case (1)
        sma_t   = Norm(pos_d) * (1d0 + rho) / 2d0 + 1d-10
      case (2)
        offset  = modulo(TAtoMA(Angle(orbit2%axis_p, axis, orbit2%axis_w), orbit2%ecc) - orbit1%ma, PI2) / orbit1%mm
        date_a  = date + offset / 86400d0
        orbit_a = orbit2%CalcOrbit(date_a)
        pos_a   = orbit_a%GetPosition()
        sma_t   = (Norm(pos_d) + Norm(pos_a)) / 2d0 + 1d-10
        sma_t   = (Norm(pos_d) + orbit_a%sma - 30d0) / 2d0
      case (3)
        sma_t   = Norm(pos_d) + 1d-10
      end select
      axis_t  = Rotate(orbit_d%axis_w, axis, theta * t(i))
      orbit_t = GetOrbit(pos_d, sma_t, axis_t, date_d)

      vel_t   = orbit_t%GetVelocity()
      del_v   = del_v + Norm(vel_t - vel_d)

      date    = date_d + orbit_t%prd * n(i) / 86400d0
      orbit1  = orbit_t%CalcOrbit(date)
      orbit2  = orbit2%CalcOrbit(date)
    end do

    tof      = CalcPeriod((orbit1%sma + orbit2%sma) / 2d0) * dnu
    orbit1_a = orbit1%CalcOrbit(date + tof / 86400d0)
    orbit2_a = orbit2%CalcOrbit(date + tof / 86400d0)
    offset   = modulo(Sgn(orbit2_a%mm - orbit1_a%mm)                                                     &
                 * (TAtoMA(Angle(orbit2_a%axis_p, orbit1_a%GetPosition(), orbit2_a%axis_w), orbit2_a%ecc) &
                 - orbit2_a%ma), PI2) / abs(orbit2_a%mm - orbit1_a%mm)
    date_d   = date + offset / 86400d0 + 1d-1
    orbit_d  = orbit1%CalcOrbit(date_d)
    pos_d    = orbit_d%GetPosition()
    vel_d    = orbit_d%GetVelocity()

    orbit_a  = orbit2%CalcOrbit(date_d + tof / 86400d0)
    pos_a    = orbit_a%GetPosition()
    vel_a    = orbit_a%GetVelocity()

    call CalcLambert(date_d, tof, pos_d, pos_a, orbit_a%axis_w, v1, v2, orbit1)
    del_v    = del_v + Norm(v1 - vel_d)
    del_v    = del_v + Norm(vel_a - v2)

    del_t    = date_d - date_s + tof / 86400d0
  end subroutine Transfer

  pure real(8) function MJD(year, day)
    integer, intent(in) :: year
    real(8), intent(in) :: day
    integer             :: y

    y = year - 1

    MJD = day - y / 100 + (y / 100) / 4 + int(365.25d0 * y) - 678575
  end function MJD
end module Solver_Debri
