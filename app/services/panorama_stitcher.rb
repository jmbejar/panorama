# Abstract base for stitching engines. Subclasses must implement #stitch(project)
# returning a StitchingResult. Per AGENTS.md / spec, controllers and views never
# touch this directly — only StitchPanoramaJob does.
class PanoramaStitcher
  def stitch(_project)
    raise NotImplementedError, "#{self.class.name} must implement #stitch(project)"
  end

  def engine_name
    raise NotImplementedError, "#{self.class.name} must implement #engine_name"
  end
end
