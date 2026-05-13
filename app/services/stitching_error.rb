# Base class for all stitching failures surfaced by a PanoramaStitcher
# implementation. Subclasses live in sibling files:
#
#   - StitchingInputError:  source photos missing, unreadable, or malformed
#   - StitchingEngineError: the external engine itself failed (Hugin crash, missing CLI, etc.)
#   - StitchingOutputError: engine completed but produced no usable output
class StitchingError < StandardError; end
