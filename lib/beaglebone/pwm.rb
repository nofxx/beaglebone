# == pwm.rb
# This file contains the PWM control methods
module Beaglebone #:nodoc:
  # == PWM
  # procedural methods for PWM control
  # == Summary
  # #start is called to enable a PWM pin
  # BBB pwm https://mcututorials.wordpress.com/2017/01/24/beaglebone-black-pwm-on-ubuntu-16-04-using-device-tree/amp/
  module PWM
    # Polarity hash
    # OLD POLARITIES = { :NORMAL => 0, :INVERTED => 1 }
    POLARITIES = { NORMAL: 'normal', INVERTED: 'inverted' }.freeze

    class << self
      # Initialize a PWM pin
      #
      # @param pin should be a symbol representing the header pin
      # @param duty should specify the duty cycle
      # @param frequency should specify cycles per second
      # @param polarity optional, should specify the polarity, :NORMAL or :INVERTED
      # @param run optional, if false, pin will be configured but will not run
      #
      # @example
      #   PWM.start(:P9_14, 90, 10, :NORMAL)
      def start(pin, duty = nil, frequency = nil, polarity = nil, run = true)
        # make sure the pwm controller dtb is loaded
        Beaglebone.device_tree_load(TREES[:PWM][:global])

        Beaglebone.check_valid_pin(pin, :pwm)

        # if pin is enabled for something else, disable it
        if Beaglebone.get_pin_status(pin) && Beaglebone.get_pin_status(pin, :type) != :pwm
          Beaglebone.disable_pin(pin)
        end

        # load device tree for pin if not already loaded
        unless Beaglebone.get_pin_status(pin, :type) == :pwm
          mod = case pin
                when /P9_21|P9_22/ then '0'
                when /P9_14|P9_16/ then '1'
                when /P9_13|P9_19/ then '2'
                end
          # OLD Beaglebone::device_tree_load("#{TREES[:PWM][:pin]}#{pin}", 0.5)
          Beaglebone.device_tree_load("#{TREES[:PWM][:pin]}#{mod}", 0.5)
          Beaglebone.set_pin_status(pin, :type, :pwm)
        end

        # OLD duty_fd = File.open("#{pwm_directory(pin)}/duty", 'r+')
        duty_fd = File.open("#{pwm_directory(pin)}/duty_cycle", 'r+')
        period_fd = File.open("#{pwm_directory(pin)}/period", 'r+')
        polarity_fd = File.open("#{pwm_directory(pin)}/polarity", 'r+')
        # OLD run_fd = File.open("#{pwm_directory(pin)}/run", 'r+')
        run_fd = File.open("#{pwm_directory(pin)}/enable", 'r+')

        Beaglebone.set_pin_status(pin, :fd_duty, duty_fd)
        Beaglebone.set_pin_status(pin, :fd_period, period_fd)
        Beaglebone.set_pin_status(pin, :fd_polarity, polarity_fd)
        Beaglebone.set_pin_status(pin, :fd_run, run_fd)

        read_period_value(pin)
        read_duty_value(pin)
        read_polarity_value(pin)

        run_fd.write('0')
        run_fd.flush

        set_polarity(pin, polarity) if polarity
        set_frequency(pin, frequency) if frequency
        set_duty_cycle(pin, duty) if duty

        if run
          run_fd.write('1')
          run_fd.flush
        end

        raise StandardError, "Could not start PWM: #{pin}" unless read_run_value(pin) == 1
        true
      end

      # Returns true if specified pin is enabled in PWM mode, else false
      def enabled?(pin)
        return true if Beaglebone.get_pin_status(pin, :type) == :pwm

        return false unless valid?(pin)
        if Dir.exist?(pwm_directory(pin))

          start(pin, nil, nil, nil, false)
          return true
        end
        false
      end

      # Stop PWM output on specified pin
      #
      # @param pin should be a symbol representing the header pin
      def stop(pin)
        Beaglebone.check_valid_pin(pin, :pwm)

        return false unless enabled?(pin)

        raise StandardError, "Pin is not PWM enabled: #{pin}" unless Beaglebone.get_pin_status(pin, :type) == :pwm

        run_fd = Beaglebone.get_pin_status(pin, :fd_run)

        raise StandardError, "Pin is not PWM enabled: #{pin}" unless run_fd

        run_fd.write('0')
        run_fd.flush

        raise StandardError, "Could not stop PWM: #{pin}" unless read_run_value(pin) == 0
        true
      end

      # Start PWM output on specified pin.  Pin must have been previously started
      #
      # @param pin should be a symbol representing the header pin
      def run(pin)
        Beaglebone.check_valid_pin(pin, :pwm)

        return false unless enabled?(pin)

        raise StandardError, "Pin is not PWM enabled: #{pin}" unless Beaglebone.get_pin_status(pin, :type) == :pwm

        run_fd = Beaglebone.get_pin_status(pin, :fd_run)

        raise StandardError, "Pin is not PWM enabled: #{pin}" unless run_fd

        run_fd.write('1')
        run_fd.flush

        raise StandardError, "Could not start PWM: #{pin}" unless read_run_value(pin) == 1
        true
      end

      # Set polarity on specified pin
      #
      # @param pin should be a symbol representing the header pin
      # @param polarity should specify the polarity, :NORMAL or :INVERTED
      # @example
      #   PWM.set_polarity(:P9_14, :INVERTED)
      def set_polarity(pin, polarity)
        check_valid_polarity(polarity)
        check_pwm_enabled(pin)

        polarity_fd = Beaglebone.get_pin_status(pin, :fd_polarity)
        raise StandardError, "Pin is not PWM enabled: #{pin}" unless polarity_fd

        polarity_fd.write(POLARITIES[polarity.to_sym].to_s)
        polarity_fd.flush

        raise StandardError, "Could not set polarity: #{pin}" unless read_polarity_value(pin) == POLARITIES[polarity.to_sym]
      end

      # Set duty cycle of specified pin in percentage
      #
      # @param pin should be a symbol representing the header pin
      # @param duty should specify the duty cycle in percentage
      # @example
      #   PWM.set_duty_cycle(:P9_14, 25)
      def set_duty_cycle(pin, duty, newperiod = nil)
        raise ArgumentError, "Duty cycle must be >= 0 and <= 100, #{duty} invalid" if duty < 0 || duty > 100
        check_pwm_enabled(pin)

        fd = Beaglebone.get_pin_status(pin, :fd_duty)
        raise StandardError, "Pin is not PWM enabled: #{pin}" unless fd

        period = newperiod || Beaglebone.get_pin_status(pin, :period)

        value = ((duty * period) / 100.0).round

        fd.write(value.to_s)
        fd.flush

        raise StandardError, "Could not set duty cycle: #{pin} (#{value})" unless read_duty_value(pin) == value

        Beaglebone.set_pin_status(pin, :duty_pct, duty)
        value
      end

      # Set duty cycle of specified pin in nanoseconds
      #
      # @param pin should be a symbol representing the header pin
      # @param duty should specify the duty cycle in nanoseconds
      # @example
      #   PWM.set_duty_cycle_ns(:P9_14, 2500000)
      def set_duty_cycle_ns(pin, duty)
        check_pwm_enabled(pin)

        fd = Beaglebone.get_pin_status(pin, :fd_duty)
        raise StandardError, "Pin is not PWM enabled: #{pin}" unless fd

        period = Beaglebone.get_pin_status(pin, :period)

        duty = duty.to_i

        if duty < 0 || duty > period
          raise ArgumentError, "Duty cycle ns must be >= 0 and <= #{period} (current period), #{duty} invalid"
        end

        value = duty

        fd.write(value.to_s)
        fd.flush

        # since we're setting the duty_ns, we want to update the duty_pct value as well here.
        raise StandardError, "Could not set duty cycle: #{pin} (#{value})" unless read_duty_value(pin, true) == value

        value
      end

      # Set frequency of specified pin in cycles per second
      #
      # @param pin should be a symbol representing the header pin
      # @param frequency should specify the frequency in cycles per second
      # @example
      #   PWM.set_frequency(:P9_14, 100)
      def set_frequency(pin, frequency)
        frequency = frequency.to_i
        raise ArgumentError, "Frequency must be > 0 and <= 1000000000, #{frequency} invalid" if frequency < 1 || frequency > 1_000_000_000
        check_pwm_enabled(pin)

        fd = Beaglebone.get_pin_status(pin, :fd_period)
        raise StandardError, "Pin is not PWM enabled: #{pin}" unless fd

        duty_ns = Beaglebone.get_pin_status(pin, :duty)
        duty_pct = Beaglebone.get_pin_status(pin, :duty_pct)

        value = (1_000_000_000 / frequency).round

        # we can't set the frequency lower than the previous duty cycle
        # adjust if necessary
        if duty_ns > value
          set_duty_cycle(pin, Beaglebone.get_pin_status(pin, :duty_pct), value)
        end

        fd.write(value.to_s)
        fd.flush

        raise StandardError, "Could not set frequency: #{pin} (#{value})" unless read_period_value(pin) == value

        # adjust the duty cycle if we haven't already
        set_duty_cycle(pin, duty_pct, value) if duty_ns <= value

        value
      end

      # Set frequency of specified pin based on period duration
      #
      # @param pin should be a symbol representing the header pin
      # @param period should specify the length of a cycle in nanoseconds
      #
      # @example
      #   PWM.set_frequency_ns(:P9_14, 100000000)
      def set_period_ns(pin, period)
        period = period.to_i
        raise ArgumentError, "period must be > 0 and <= 1000000000, #{period} invalid" if period < 1 || period > 1_000_000_000
        check_pwm_enabled(pin)

        fd = Beaglebone.get_pin_status(pin, :fd_period)
        raise StandardError, "Pin is not PWM enabled: #{pin}" unless fd

        duty_ns = Beaglebone.get_pin_status(pin, :duty)
        value = period.to_i

        # we can't set the frequency lower than the previous duty cycle
        # adjust if necessary
        if duty_ns > value
          set_duty_cycle(pin, Beaglebone.get_pin_status(pin, :duty_pct), value)
        end

        fd.write(value.to_s)
        fd.flush

        raise StandardError, "Could not set period: #{pin} (#{value})" unless read_period_value(pin) == value

        # adjust the duty cycle if we haven't already
        if duty_ns <= value
          set_duty_cycle(pin, Beaglebone.get_pin_status(pin, :duty_pct), value)
        end

        value
      end

      # reset all PWM pins we've used to IN and unexport them
      def cleanup
        get_pwm_pins.each { |x| disable_pwm_pin(x) }
      end

      # Return an array of PWM pins in use
      #
      # @return [Array<Symbol>]
      #
      # @example
      #   PWM.get_pwm_pins => [:P9_13, :P9_14]
      def get_pwm_pins
        Beaglebone.pinstatus.clone.select { |x, y| x if y[:type] == :pwm }.keys
      end

      # Disable a PWM pin
      #
      # @param pin should be a symbol representing the header pin
      def disable_pwm_pin(pin)
        Beaglebone.check_valid_pin(pin, :pwm)
        Beaglebone.delete_pin_status(pin) if Beaglebone.device_tree_unload("#{TREES[:PWM][:pin]}#{pin}")
      end

      private

      # ensure pin is valid pwm pin
      def valid?(pin)
        # check to see if pin exists
        pin = pin.to_sym

        return false unless PINS[pin]
        return false unless PINS[pin][:pwm]

        true
      end

      # ensure pin is pwm enabled
      def check_pwm_enabled(pin)
        raise StandardError, "Pin is not PWM enabled: #{pin}" unless enabled?(pin)
      end

      # read run file
      def read_run_value(pin)
        check_pwm_enabled(pin)

        fd = Beaglebone.get_pin_status(pin, :fd_run)
        raise StandardError, "Pin is not PWM enabled: #{pin}" unless fd

        fd.rewind
        fd.read.strip.to_i
      end

      # read polarity file
      def read_polarity_value(pin)
        check_pwm_enabled(pin)

        fd = Beaglebone.get_pin_status(pin, :fd_polarity)
        raise StandardError, "Pin is not PWM enabled: #{pin}" unless fd

        fd.rewind
        # OLD value = fd.read.strip #.to_i
        value = fd.read.strip # .to_i

        Beaglebone.set_pin_status(pin, :polarity, value)
      end

      # read duty file
      def read_duty_value(pin, setpct = false)
        check_pwm_enabled(pin)

        fd = Beaglebone.get_pin_status(pin, :fd_duty)
        raise StandardError, "Pin is not PWM enabled: #{pin}" unless fd

        fd.rewind
        value = fd.read.strip.to_i

        Beaglebone.set_pin_status(pin, :duty, value)
        # only set duty_pct if it is unset or if we are forcing it.
        if setpct || Beaglebone.get_pin_status(pin, :duty_pct).nil?
          duty_pct = ((value * 100.0) / Beaglebone.get_pin_status(pin, :period)).round
          Beaglebone.set_pin_status(pin, :duty_pct, duty_pct)
        end

        value
      end

      # read period file
      def read_period_value(pin)
        check_pwm_enabled(pin)

        fd = Beaglebone.get_pin_status(pin, :fd_period)
        raise StandardError, "Pin is not PWM enabled: #{pin}" unless fd

        fd.rewind
        value = fd.read.strip.to_i

        Beaglebone.set_pin_status(pin, :period, value)

        value
      end

      # return sysfs directory for pwm control
      def pwm_directory(pin)
        raise StandardError, 'Invalid Pin' unless valid?(pin)
        # OLD Dir.glob("/sys/devices/ocp.*/pwm_test_#{pin}.*").first
        mod = case pin
              when /P9_21|P9_22/ then '2'
              when /P9_14|P9_16/ then '4'
              when /P9_13|P9_19/ then '6'
              end
        Dir.glob("/sys/class/pwm/pwmchip#{mod}/pwm0").first
      end

      # ensure polarity is valid
      def check_valid_polarity(polarity)
        # check to see if mode is valid
        polarity = polarity.to_sym
        raise ArgumentError, "No such polarity: #{polarity}" unless POLARITIES.include?(polarity)
      end
    end
  end

  # Object Oriented PWM Implementation.
  # This treats the pin as an object.
  class PWMPin
    # Initialize a PWM pin
    #
    #
    # @param duty should specify the duty cycle
    # @param frequency should specify cycles per second
    # @param polarity optional, should specify the polarity, :NORMAL or :INVERTED
    # @param run optional, if false, pin will be configured but will not run
    #
    # @example
    #   p9_14 = PWMPin.new(:P9_14, 90, 10, :NORMAL)
    def initialize(pin, duty = nil, frequency = nil, polarity = nil, run = true)
      @pin = pin
      PWM.start(@pin, duty, frequency, polarity, run)
    end

    # Stop PWM output on pin
    def stop
      PWM.stop(@pin)
    end

    # Start PWM output on pin.  Pin must have been previously started
    def run
      PWM.run(@pin)
    end

    # Set polarity on pin
    #
    # @param polarity should specify the polarity, :NORMAL or :INVERTED
    # @example
    #   p9_14.set_polarity(:INVERTED)
    def set_polarity(polarity)
      PWM.set_polarity(@pin, polarity)
    end

    # Set duty cycle of pin in percentage
    #
    #
    # @param duty should specify the duty cycle in percentage
    # @example
    #   p9_14.set_duty_cycle(25)
    def set_duty_cycle(duty, newperiod = nil)
      PWM.set_duty_cycle(@pin, duty, newperiod)
    end

    # Set duty cycle of pin in nanoseconds
    #
    # @param duty should specify the duty cycle in nanoseconds
    # @example
    #   p9_14.set_duty_cycle_ns(2500000)
    def set_duty_cycle_ns(duty)
      PWM.set_duty_cycle_ns(@pin, duty)
    end

    # Set frequency of pin in cycles per second
    #
    # @param frequency should specify the frequency in cycles per second
    # @example
    #   p9_14.set_frequency(100)
    def set_frequency(frequency)
      PWM.set_frequency(@pin, frequency)
    end

    # Set frequency of pin based on period duration
    #
    # @param period should specify the length of a cycle in nanoseconds
    # @example
    #   p9_14.set_frequency_ns(100000000)
    def set_period_ns(period)
      PWM.set_period_ns(@pin, period)
    end

    # Disable PWM pin
    def disable_pwm_pin
      PWM.disable_pwm_pin(@pin)
    end
  end
end
