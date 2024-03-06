import net
import http
import .globals
import encoding.json
import .a4988 show stepper_motor STORAGE
import hx711 show Hx711 Hx711Input

MOTOR /stepper_motor := ?
SCALE /Hx711 := ?
TARE /num := ?

calc_weight value:
  y := MAX_WEIGHT * (value + 1)
  tare := MAX_WEIGHT * (TARE + 1)
  return y - tare

ROUTER := {
    "/": :: | request/http.Request writer/http.ResponseWriter |
      writer.write_headers http.STATUS_OK
      writer.write "test",
    "/red": :: | request/http.Request writer/http.ResponseWriter |
      RED_LED.set 1
      writer.write_headers http.STATUS_OK
      writer.write "OK",
    "/green": :: | request/http.Request writer/http.ResponseWriter |
      GREEN_LED.set 1
      writer.write_headers http.STATUS_OK
      writer.write "OK",
    "/ledoff": :: | request/http.Request writer/http.ResponseWriter |
      GREEN_LED.set 0
      RED_LED.set   0
      writer.write_headers http.STATUS_OK
      writer.write "OK",
    "/unload": :: | request/http.Request writer/http.ResponseWriter |
      MOTOR.rotate UNLOAD_ANGLE
      writer.write_headers http.STATUS_OK
      writer.write "OK",
    "/restore": :: | request/http.Request writer/http.ResponseWriter |
      MOTOR.reset
      writer.write_headers http.STATUS_OK
      writer.write "OK",
    "/weight": :: | request/http.Request writer/http.ResponseWriter |
      weight := calc_weight (SCALE.average_of_10 Hx711.CHANNEL_A_GAIN_128)
      writer.write_headers http.STATUS_OK
      writer.write "$weight",
    "/recalibrate": :: | request/http.Request writer/http.ResponseWriter |
      weight := 365.0 / (SCALE.average_of_10 Hx711.CHANNEL_A_GAIN_128)
      writer.write_headers http.STATUS_OK
      writer.write "$weight",
    "/reset": :: | request/http.Request writer/http.ResponseWriter |
      MOTOR.reset
      GREEN_LED.set 0
      RED_LED.set   0
      writer.write_headers http.STATUS_OK
      writer.write "OK",
}

start_listen port/int:
  network := net.open
  tcp_socket := network.tcp_listen port
  server := http.Server
  handler := ::
    it.print "HTTP handler"
  task:: server.listen
    tcp_socket:: | request/http.Request writer/http.ResponseWriter |
    fn /Lambda? := ROUTER.get request.path 
    if fn:
      fn.call request writer
    writer.close
  print "Listener started!"

start_logic:
  MOTOR = stepper_motor STEPS STEP_PIN DIR_PIN
  MOTOR.begin RPM MICROSTEPS
  MOTOR.reset // return to 0 location?
  print "Motor initialized"
  SCALE = Hx711 --clock=ADC_CLK --data=ADC_DOUT
  TARE = SCALE.average_of_10 Hx711.CHANNEL_A_GAIN_128
  print "Scale initialized. Tare: $TARE"
  task:: start_listen PORT
