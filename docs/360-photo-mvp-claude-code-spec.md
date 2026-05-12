# Claude Code Spec: MVP 360 Photo Assembly App

## Goal

Build an MVP app where a user uploads a series of photos of their surroundings, and the system helps assemble them into a 360-degree panoramic photo.

This MVP should prioritize validating the product workflow over inventing a custom stitching algorithm.

The expected flow is:

1. User creates a new panorama project.
2. User uploads a sequence of overlapping photos.
3. App validates the upload quality.
4. Backend runs a stitching job using an existing stitching engine.
5. App produces an equirectangular panorama image.
6. User previews the result in a 360 viewer.
7. User can download the final panorama.

## Product Scope

### In scope

- Web-based MVP.
- User can create a panorama project.
- User can upload multiple images.
- User can see upload progress.
- User can see basic validation warnings.
- Backend processes photos asynchronously.
- Backend stitches images using an existing CLI/tooling pipeline.
- User can preview the stitched 360 image.
- User can download the resulting image.
- Store projects, source images, processing status, logs, and final output.

### Out of scope for MVP

- Native mobile capture guidance.
- Real-time camera capture.
- Custom computer vision stitching implementation.
- AI image generation / gap filling.
- Advanced account/team billing.
- Social sharing.
- Editing tools.
- Manual control point editing.
- Support for video input.

## Suggested Tech Stack

Prefer a pragmatic stack that can be built quickly.

Recommended default:

- Rails 8 app.
- SQLite for MVP persistence.
- Solid Queue for background jobs.
- Active Storage for image uploads and output files.
- Hugin CLI / Panorama Tools for initial stitching pipeline.
- Optional OpenCV fallback or later experiment.
- React or plain Rails views for UI, depending on existing app preference.
- Three.js or Marzipano for 360 preview.

If the current repo already has a preferred frontend/backend architecture, adapt to it, but keep the same domain model and workflow.

## Important Technical Direction

Do not build a custom stitching algorithm for the MVP.

Use an external stitching engine through a backend job. The MVP should be designed so the stitching engine can be swapped later.

Create a clear abstraction:

```ruby
class PanoramaStitcher
  def stitch(project)
    # returns a StitchingResult
  end
end
```

Start with a CLI-based implementation:

```ruby
class HuginPanoramaStitcher < PanoramaStitcher
end
```

The app should capture logs and errors from the stitching process so we can diagnose failed projects.

## Domain Model

Create these core models or equivalent structures.

### PanoramaProject

Fields:

- `id`
- `title`
- `status`
- `created_at`
- `updated_at`
- `processing_started_at`
- `processing_finished_at`
- `failure_reason`
- `stitching_engine`
- `stitching_logs`

Statuses:

- `draft`
- `uploaded`
- `validating`
- `ready_to_process`
- `processing`
- `completed`
- `failed`

Associations:

- has many source photos
- has one final panorama image through Active Storage or equivalent

### SourcePhoto

Fields:

- `id`
- `panorama_project_id`
- `position`
- `filename`
- `content_type`
- `width`
- `height`
- `file_size`
- `exif_data`
- `validation_status`
- `validation_warnings`

Associations:

- belongs to panorama project
- has one attached image

### StitchingJob / ProcessingLog, optional

If helpful, create a separate model for job attempts.

Fields:

- `panorama_project_id`
- `status`
- `engine`
- `started_at`
- `finished_at`
- `stdout`
- `stderr`
- `exit_code`
- `error_message`

## Upload Requirements

Allow users to upload between 6 and 60 photos.

For MVP, assume the user uploads photos in approximate left-to-right capture order.

Accepted formats:

- JPEG
- PNG, optional
- HEIC only if the stack can reliably convert it server-side

Validation rules:

- Minimum number of images: 6
- Maximum number of images: 60
- Minimum image width: 1200 px
- Warn if images have mixed dimensions
- Warn if images have very different aspect ratios
- Warn if files are too small or possibly compressed too much
- Warn if EXIF orientation is missing or inconsistent
- Warn if images appear unordered, if detectable

Validation should not be overly strict. The goal is to help the user understand why stitching might fail, not block every imperfect input.

## Stitching Pipeline

Create a service object that prepares a temporary working directory:

```text
/tmp/panorama_projects/:project_id/
  input/
  output/
  logs/
```

Steps:

1. Download Active Storage source images into `input/`.
2. Normalize orientation.
3. Convert unsupported formats if needed.
4. Call the selected stitching engine.
5. Capture stdout/stderr.
6. Store intermediate logs.
7. Attach the final stitched image to the project.
8. Update project status.
9. Clean temporary files, unless debugging is enabled.

### Hugin CLI direction

Investigate and implement a minimal automated Hugin pipeline using available command-line tools.

Likely tools may include:

- `pto_gen`
- `cpfind`
- `cpclean`
- `linefind`, optional
- `autooptimiser`
- `pano_modify`
- `nona`
- `enblend`
- `hugin_executor`, if available and practical

The exact command sequence may depend on the installed Hugin version. Implement it behind the `HuginPanoramaStitcher` class and document the final working command chain in code comments.

The generated final image should ideally be an equirectangular JPEG.

If full spherical stitching is unreliable, allow a cylindrical panorama as an MVP fallback, but label it clearly in the UI as not a full 360 sphere.

## 360 Metadata

Add metadata support later in the MVP if straightforward.

Goal: final JPEG should be recognizable by compatible viewers as a panorama / photo sphere.

Create a dedicated service:

```ruby
class PhotoSphereMetadataWriter
  def write!(image_path, metadata: {})
  end
end
```

Minimum useful metadata:

- Projection type: equirectangular
- Full pano width
- Full pano height
- Cropped area width
- Cropped area height
- Cropped area left
- Cropped area top

If this becomes time-consuming, keep it as a separate TODO and rely on the in-app viewer for MVP validation.

## UI Flow

### Page 1: Project index

Show:

- List of panorama projects.
- Status badge.
- Created date.
- Link to view each project.
- Button: “New panorama”.

### Page 2: New project

Fields:

- Project title.
- Upload zone for multiple photos.

UX copy:

> Upload a sequence of overlapping photos taken while rotating in place. For best results, keep the camera position stable and overlap each photo by 30–50%.

### Page 3: Project detail / upload review

Show:

- Uploaded thumbnails in order.
- Drag-and-drop reorder if feasible.
- Basic metadata for each photo.
- Validation warnings.
- Button: “Generate 360 photo”.

### Page 4: Processing state

Show:

- Current status.
- Spinner/progress state.
- Last log line or friendly processing message.
- Auto-refresh or polling.

### Page 5: Completed result

Show:

- 360 interactive preview.
- Flat equirectangular preview.
- Download button.
- Button to start over / create another.
- Basic diagnostic info: number of photos, processing time, stitching engine.

### Page 6: Failed state

Show:

- Friendly error message.
- Common reasons:
  - Not enough overlap.
  - Photos were not captured from the same point.
  - Moving people/objects caused conflicts.
  - Too few photos.
  - Low texture scene.
- Show captured logs only in developer/debug mode.
- Allow user to reorder or replace images and retry.

## 360 Viewer

Use a browser-based viewer.

Good options:

- Three.js with sphere geometry and equirectangular texture.
- Marzipano.
- Photo Sphere Viewer.

Implement a simple component:

```text
PanoramaViewer
  props:
    imageUrl
```

Requirements:

- User can drag to look around.
- Mouse wheel or pinch zoom if easy.
- Works on desktop first.
- Mobile browser support is nice-to-have.

## Capture Guidance Copy

Include a lightweight guidance panel before upload:

Title:

> How to capture better 360 photos

Bullets:

- Stand in one place and rotate your body, not the camera position.
- Keep each photo overlapping the previous one by 30–50%.
- Avoid people or cars moving through the scene.
- Keep exposure as consistent as possible.
- Capture enough photos to cover the full circle.
- For a full sphere, capture additional rows for ceiling and floor coverage.

## Quality Checks

Implement simple checks first.

### Before processing

- Count photos.
- Dimensions consistency.
- Orientation consistency.
- File size sanity.
- EXIF availability.

### After processing

- Confirm output file exists.
- Confirm output dimensions are plausible.
- Confirm image can be loaded by the viewer.
- Mark project as failed if output is missing or too small.

## Background Job

Create a job:

```ruby
class StitchPanoramaJob < ApplicationJob
  def perform(panorama_project_id)
  end
end
```

Behavior:

- Set project status to `processing`.
- Run validation.
- Run stitcher.
- Attach final image.
- Set status to `completed`.
- On error, set status to `failed` and persist failure reason/logs.

Make the job idempotent enough to retry.

## Error Handling

Use explicit error classes:

```ruby
class StitchingError < StandardError; end
class StitchingInputError < StitchingError; end
class StitchingEngineError < StitchingError; end
class StitchingOutputError < StitchingError; end
```

Do not expose raw command-line errors directly to normal users.

Persist raw logs for debugging.

## Developer Setup

Document required system dependencies.

Example:

```bash
brew install hugin exiftool imagemagick
```

Or Docker-based alternative:

```Dockerfile
RUN apt-get update && apt-get install -y hugin-tools exiftool imagemagick
```

Claude Code should inspect the target environment and choose the most reliable installation path.

## Testing Strategy

Add tests around the app workflow, but avoid brittle tests around actual Hugin output unless sample fixtures are available.

Recommended tests:

- Project creation.
- Multiple image upload.
- Source photo ordering.
- Validation warnings.
- Job status transitions.
- Stitcher abstraction using a fake stitcher.
- Failed stitching path.
- Completed stitching path with a fixture output image.

Create a fake stitcher for tests:

```ruby
class FakePanoramaStitcher
  def stitch(project)
    # returns a fixture image as if it were stitched
  end
end
```

## Implementation Phases

### Phase 1: Skeleton workflow

- Create models.
- Create project UI.
- Create upload flow.
- Store images.
- Show thumbnails and status.

### Phase 2: Background processing architecture

- Add `StitchPanoramaJob`.
- Add stitcher abstraction.
- Add fake stitcher.
- Implement complete happy path using fake output.

### Phase 3: Real stitching engine

- Add Hugin-based stitcher.
- Implement temp directory workflow.
- Capture logs.
- Attach generated output.
- Handle failures.

### Phase 4: 360 preview

- Add browser 360 viewer.
- Add completed result page.
- Add download button.

### Phase 5: Product polish

- Add validation warnings.
- Add better failure messages.
- Add retry flow.
- Add capture guidance.
- Add debug logs for developers.

## Acceptance Criteria

The MVP is complete when:

- A user can create a panorama project.
- A user can upload multiple photos.
- The app stores and displays the uploaded photos.
- The user can trigger panorama generation.
- The generation runs in a background job.
- The app produces a final image or a clear failure state.
- A completed project shows an interactive 360 preview.
- The user can download the output image.
- Logs are available for debugging failed stitch attempts.
- The stitching engine is isolated behind a replaceable service object.

## Coding Guidelines

- Keep the stitching integration isolated from controllers and UI.
- Prefer small service objects.
- Persist enough diagnostic data to debug failures.
- Keep user-facing errors friendly.
- Avoid premature optimization.
- Avoid building custom CV unless explicitly requested later.
- Make the app easy to run locally with documented dependencies.

## Open Questions To Leave Documented In The Codebase

- Is Hugin reliable enough for the target use case?
- Do we need native mobile capture guidance?
- Do we need full spherical output or is cylindrical panorama enough for the first validation?
- How many photos do users realistically upload?
- What capture instructions lead to successful results?
- Should we use a commercial stitcher like PTGui Pro later?
- Do we need AI-assisted quality review or capture coaching?

## First Task For Claude Code

Start by implementing Phase 1 and Phase 2 with a fake stitcher.

Do not integrate Hugin until the app workflow is working end-to-end with a fake generated output.

After Phase 2, provide:

1. A short summary of implemented files.
2. Setup instructions.
3. How to run the app.
4. How to run tests.
5. What remains for the real stitching engine integration.
