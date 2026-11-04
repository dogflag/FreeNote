# Build and Test

## CI path

`.github/workflows/build-ipa.yml` runs on `macos-15`:

1. installs XcodeGen;
2. generates `FreeNote.xcodeproj`;
3. runs the `FreeNote` scheme against a generic iOS device;
4. packages `Payload/FreeNote.app` as `build/FreeNote-unsigned.ipa`;
5. uploads the IPA as an Actions artifact.

The project is built with:

```text
CODE_SIGNING_ALLOWED=NO
CODE_SIGNING_REQUIRED=NO
```

Do not add a provisioning profile to the unsigned artifact.

## Unit tests

Expected CI command after generation:

```bash
xcodebuild \
  -project FreeNote.xcodeproj \
  -scheme FreeNote \
  -destination 'platform=iOS Simulator,name=iPad (10th generation)' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

The simulator name can vary by runner image; update the workflow if it is unavailable.

## TrollStore verification

For every IPA, record:

- iPad model;
- iPadOS version;
- TrollStore version;
- installation result;
- launch result;
- note creation and PencilKit drawing;
- PDF import, page navigation and text selection;
- file import from Files;
- outline edit and persistence after relaunch;
- light/dark appearance.

A test is successful only after the app launches on the device. A successful CI build alone does not prove TrollStore compatibility.
