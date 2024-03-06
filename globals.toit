import gpio

// HTTP settings
PORT/int ::= 8888

// Pin-out settings
GREEN_LED ::= gpio.Pin.out 25
RED_LED ::= gpio.Pin.out 26
ADC_DOUT ::= gpio.Pin 16
ADC_CLK ::= gpio.Pin 17
DIR_PIN ::= 4
STEP_PIN ::= 0

// Motor settings
RPM/float ::= 200.0
STEPS/int ::= 200
MICROSTEPS/int ::= 1

// Common settings
UNLOAD_ANGLE/int ::= 360
MAX_WEIGHT/float ::= 1000.0
