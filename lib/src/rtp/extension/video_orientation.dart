import 'extension.dart';

class VideoOrientationExtension  extends HeaderExtension{
  CameraDirection direction;
  bool flip;
  VideoRotation rotation;

  VideoOrientationExtension(this.direction, this.flip, this.rotation);
}

enum CameraDirection {
  Front(0),
  Back(1);

  const CameraDirection(this.value);
  final int value;
}

enum VideoRotation {
  Degree0(0),
  Degree90(1),
  Degree180(2),
  Degree270(3);

  const VideoRotation(this.value);
  final int value;
}
