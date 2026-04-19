proc fail {message} {
    puts stderr $message
    catch {close_hw_target}
    catch {disconnect_hw_server}
    catch {close_hw_manager}
    exit 1
}

set bitstream_path ""
set device_index ""
set list_only 0

for {set idx 0} {$idx < [llength $argv]} {incr idx} {
    set arg [lindex $argv $idx]
    switch -- $arg {
        -bitstream {
            incr idx
            if {$idx >= [llength $argv]} {
                fail "missing value for -bitstream"
            }
            set bitstream_path [file normalize [lindex $argv $idx]]
        }
        -device-index {
            incr idx
            if {$idx >= [llength $argv]} {
                fail "missing value for -device-index"
            }
            set device_index [lindex $argv $idx]
        }
        -list-only {
            set list_only 1
        }
        default {
            fail "unknown argument: $arg"
        }
    }
}

open_hw_manager
connect_hw_server
open_hw_target

set devices [get_hw_devices]
if {[llength $devices] == 0} {
    fail "no JTAG devices found"
}

for {set idx 0} {$idx < [llength $devices]} {incr idx} {
    set dev [lindex $devices $idx]
    puts "HW_DEVICE_INDEX:$idx NAME:[get_property NAME $dev] PART:[get_property PART $dev]"
}

if {$list_only} {
    close_hw_target
    disconnect_hw_server
    close_hw_manager
    exit 0
}

if {$bitstream_path eq ""} {
    fail "missing -bitstream"
}

if {![file exists $bitstream_path]} {
    fail "bitstream not found: $bitstream_path"
}

if {$device_index eq ""} {
    if {[llength $devices] == 1} {
        set device_index 0
    } else {
        fail "multiple JTAG devices found; pass -device-index"
    }
}

if {![string is integer -strict $device_index]} {
    fail "device index must be an integer: $device_index"
}

if {$device_index < 0 || $device_index >= [llength $devices]} {
    fail "device index out of range: $device_index"
}

set dev [lindex $devices $device_index]
current_hw_device $dev
refresh_hw_device -update_hw_probes false $dev
set_property PROGRAM.FILE $bitstream_path $dev
program_hw_devices $dev
refresh_hw_device -update_hw_probes false $dev

puts "PROGRAMMED_DEVICE_INDEX:$device_index"
puts "PROGRAMMED_DEVICE_NAME:[get_property NAME $dev]"
puts "PROGRAMMED_DEVICE_PART:[get_property PART $dev]"
puts "PROGRAMMED_BITSTREAM:$bitstream_path"

close_hw_target
disconnect_hw_server
close_hw_manager
