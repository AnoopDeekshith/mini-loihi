export DESIGN_NAME = snn_top
export PLATFORM    = sky130hs
export VERILOG_FILES = $(DESIGN_DIR)/src/snn_top_mapped.v
export SDC_FILE      = $(DESIGN_DIR)/constraint.sdc
export CORE_UTILIZATION = 40
export CORE_ASPECT_RATIO = 1
export CORE_MARGIN = 2
export PLACE_DENSITY = 0.65
