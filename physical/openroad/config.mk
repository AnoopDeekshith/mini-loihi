# OpenROAD flow config for mini-loihi (snn_top)
# Used with the OpenROAD-flow-scripts (ORFS) build system targeting Sky130.
#
# Usage: make DESIGN_CONFIG=physical/openroad/config.mk

export DESIGN_NAME     = snn_top
export PLATFORM        = sky130hd

# --- RTL sources ---
export VERILOG_FILES = \
    hardware/rtl/timestep_ctrl.v \
    hardware/rtl/weight_rom.v \
    hardware/rtl/synapse_acc.v \
    hardware/rtl/lif_core.v \
    hardware/rtl/spike_router.v \
    hardware/rtl/snn_top.v

# --- Constraints ---
# TODO: provide an SDC file defining the clock and I/O timing.
# export SDC_FILE = physical/openroad/snn_top.sdc

# --- Floorplan ---
# TODO: tune utilization / aspect ratio for the final cell count.
export CORE_UTILIZATION  = 40
export PLACE_DENSITY     = 0.60
export CORE_ASPECT_RATIO = 1.0
