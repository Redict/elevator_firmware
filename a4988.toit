// Copyright (C) 2021 Toitware ApS. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be found
// in the LICENSE file.

// This is a driver for the 28BYJ-48 unipolar stepper motor, using
// ULN2003 driver IC to drive the stepper.
// The 28BYJ-48 motor is a 4-phase, 8-beat motor, geared down by
// a factor of 64. One bipolar winding is on motor pins 1 & 3 and
// the other on motor pins 2 & 4. 

import gpio
import math
import esp32
import system.storage as storage

STORAGE ::= storage.Bucket.open --flash "a4988"
IS_CONNECTED pin: return pin == -1 ? false : true
STEP_PULSE steps microsteps rpm -> float:
  return 60.0*1000000/steps/microsteps/rpm

// State enum
STOPPED_ ::= 0
ACCELERATING_ ::= 1
CRUISING_ ::= 2
DECELERATING_ ::= 3

class stepper_motor:
  static MAX_MICROSTEP_ ::= 16
  static MS_TABLE_      ::= #[0b000, 0b001, 0b010, 0b011, 0b111] // Half-step switching sequence

  // Hardware configuration
  step_pin_ := ?
  dir_pin_ := ?
  ms1_pin_ := ?
  ms2_pin_ := ?
  ms3_pin_ := ?
  steps_  := ? // number of steps per full revolution
  step_angle_ := ?  // = 0.703125 degrees
  step_high_min_ := 1
  microsteps_ := 0
  rpm_ := 0.0

  // Logic configuration
  steps_to_cruise_ := ?
  steps_remaining_ := ?
  dir_state_ := ?
  steps_to_brake_ := ?
  step_pulse_ := ?
  cruise_step_pulse_ := ?
  rest_ := ?
  step_count_ := ?
  last_action_end_ := 0
  next_action_interval_ := 0


  constructor steps/int step_pin/int dir_pin/int:
    step_pin_ = gpio.Pin.out step_pin
    dir_pin_  = gpio.Pin.out dir_pin
    steps_ = steps
    step_angle_ = 360.0 / steps_
    ms1_pin_ = -1
    ms2_pin_ = -1
    ms3_pin_ = -1
    steps_to_cruise_ = 0
    steps_remaining_ = 0
    dir_state_ = 0
    steps_to_brake_ = 0
    step_pulse_ = 0
    cruise_step_pulse_ = 0
    rest_ = 0
    step_count_ = 0

  constructor \
    steps/int \
    step_pin/int \
    dir_pin/int \
    ms1_pin/int \
    ms2_pin/int \
    ms3_pin/int:
    step_pin_ = gpio.Pin step_pin
    dir_pin_  = gpio.Pin dir_pin 
    ms1_pin_  = gpio.Pin ms1_pin
    ms2_pin_  = gpio.Pin ms2_pin
    ms3_pin_  = gpio.Pin ms3_pin
    steps_ = steps
    step_angle_ = 360.0 / steps_
    steps_to_cruise_ = 0
    steps_remaining_ = 0
    dir_state_ = 0
    steps_to_brake_ = 0
    step_pulse_ = 0
    cruise_step_pulse_ = 0
    rest_ = 0
    step_count_ = 0

  begin rpm/float microsteps/int:
    dir_pin_.config --output
    dir_pin_.set 1
    
    step_pin_.config --output
    step_pin_.set 0

    rpm_ = rpm
    set_microstep microsteps
    
    if \
    not IS_CONNECTED (ms1_pin_) or \
    not IS_CONNECTED (ms2_pin_) or \
    not IS_CONNECTED (ms3_pin_):
      return
    ms1_pin_.config --output
    ms2_pin_.config --output
    ms3_pin_.config --output

  set_microstep microsteps/int:
    microsteps = microsteps & 0xffff
    // Convert to ushort
    for ms:=1;ms<=microsteps;ms<<=1:
      if microsteps==ms:
        microsteps_ = microsteps
        break

    if \
    not IS_CONNECTED (ms1_pin_) or \
    not IS_CONNECTED (ms2_pin_) or \
    not IS_CONNECTED (ms3_pin_):
      return microsteps_

    ms_table/ByteArray := get_microstep_table
    ms_table_size/int  := get_microstep_table_size
    for i:=0; i<ms_table_size; i++:
      if (microsteps_ & (1<<i)) & 0xffff:
        mask := ms_table[i]
        ms3_pin_.set (mask & 4)
        ms2_pin_.set (mask & 2)
        ms1_pin_.set (mask & 1)
    return microsteps_

  get_microstep_table:
    return MS_TABLE_

  get_microstep_table_size:
    return MS_TABLE_.size

  get_max_microsteps:
    return MAX_MICROSTEP_

  set_rpm rpm/float:
    if rpm_ == 0:
      begin rpm microsteps_
    rpm_ = rpm
  
  get_current_state:
    if steps_remaining_ <= 0:
      return STOPPED_
    if steps_remaining_ <= steps_to_brake_:
      return DECELERATING_
    else if step_count_ <= steps_to_cruise_:
      return ACCELERATING_
    return CRUISING_

  calc_step_pulse:
    if steps_remaining_ <= 0:
      return
    steps_remaining_--
    step_count_++

  delay_micros delay_us/int --start_us/int=0:
    if delay_us != 0:
      if start_us == 0:
        start_us = esp32.total_run_time
      while esp32.total_run_time - start_us < delay_us:

  next_action:
    if steps_remaining_ > 0:
      delay_micros next_action_interval_ --start_us=last_action_end_
      dir_pin_.set dir_state_
      step_pin_.set 1
      pulse ::= step_pulse_
      m := esp32.total_run_time
      calc_step_pulse
      delay_micros step_high_min_
      step_pin_.set 0
      last_action_end_ = esp32.total_run_time
      m = last_action_end_ - m
      next_action_interval_ = (pulse > m) ? (pulse - m).to_int : 1
    else:
      last_action_end_ = 0
      next_action_interval_ = 0
    return next_action_interval_

  move steps:
    start_move steps 0
    while next_action != 0:
  
  rotate deg/int:
    move (deg * steps_ * microsteps_ / 360).to_int
  
  start_move steps/int time/int:
    speed/float := ?
    dir_state_ = (steps >= 0) ? 1 : 0
    if dir_state_ == 1:
      STORAGE["angle"] += steps
    else:
      STORAGE["angle"] -= steps
    last_action_end_ = 0
    steps_remaining_ = steps.abs
    step_count_ = 0
    rest_ = 0

    // constant mode
    steps_to_cruise_ = 0
    steps_to_brake_ = 0
    step_pulse_ = cruise_step_pulse_ = STEP_PULSE steps_ microsteps_ rpm_
    if time > (steps_remaining_ * step_pulse_):
      step_pulse_ = time.to_float / steps_remaining_
  
  reset:
    move -(STORAGE.get "angle" --init=: 0)
    STORAGE["angle"] = 0
