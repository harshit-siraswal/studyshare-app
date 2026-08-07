import { Composition } from "remotion";
import { StudyShareLaunchV2 } from "./StudyShareLaunchV2";

export const RemotionRoot = () => {
  return (
    <Composition
      id="StudyShareLaunch"
      component={StudyShareLaunchV2}
      durationInFrames={3600}
      fps={30}
      width={1920}
      height={1080}
    />
  );
};
