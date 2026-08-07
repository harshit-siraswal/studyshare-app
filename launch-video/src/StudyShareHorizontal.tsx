import React, { CSSProperties } from "react";
import {
  AbsoluteFill,
  Audio,
  Easing,
  Img,
  interpolate,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { loadFont } from "@remotion/google-fonts/Inter";
import {
  AlertTriangle,
  BadgeCheck,
  BarChart3,
  Bell,
  BellRing,
  Bot,
  CalendarCheck,
  CheckCircle2,
  Clock,
  CreditCard,
  Crown,
  Download,
  FileText,
  Filter,
  Folder,
  GraduationCap,
  Home,
  MessageSquare,
  Moon,
  Plus,
  Search,
  Settings,
  Sparkles,
  Sun,
  Trophy,
  Users,
  Video,
  Zap,
  type LucideIcon,
} from "lucide-react";

const { fontFamily } = loadFont("normal", {
  weights: ["400", "500", "600", "700", "800"],
  subsets: ["latin"],
});

const C = {
  blue: "#2563EB",
  blueLight: "#3B82F6",
  blueSoft: "#93C5FD",
  orange: "#F97316",
  gold: "#FFC107",
  green: "#059669",
  bg: "#000000",
  panel: "#10141D",
  panel2: "#171B24",
  border: "#2E3545",
  text: "#F9FAFB",
  sub: "#D1D5DB",
  muted: "#7C8595",
};

const clamp = {
  extrapolateLeft: "clamp" as const,
  extrapolateRight: "clamp" as const,
};

const px = (value: number) => `${value}px`;
const sf = (seconds: number, fps: number) => Math.round(seconds * fps);

const progress = (
  frame: number,
  fps: number,
  start: number,
  end: number,
  easing = Easing.inOut(Easing.cubic),
) =>
  interpolate(frame, [sf(start, fps), sf(end, fps)], [0, 1], {
    ...clamp,
    easing,
  });

const fadeBetween = (
  frame: number,
  fps: number,
  start: number,
  end: number,
  fade = 0.45,
) => {
  const fadeFrames = sf(fade, fps);
  const startFrame = sf(start, fps);
  const endFrame = sf(end, fps);
  const fadeIn = interpolate(frame, [startFrame, startFrame + fadeFrames], [0, 1], clamp);
  const fadeOut = interpolate(frame, [endFrame - fadeFrames, endFrame], [1, 0], clamp);
  return Math.min(fadeIn, fadeOut);
};

const baseText: CSSProperties = {
  fontFamily,
  color: C.text,
  letterSpacing: 0,
};

const phone = {
  w: 430,
  h: 930,
  pad: 17,
};

type CopyScene = {
  start: number;
  end: number;
  kicker: string;
  title: string;
  body: string;
  chips: string[];
  accent?: string;
};

const copyScenes: CopyScene[] = [
  {
    start: 0,
    end: 7,
    kicker: "Launch walkthrough",
    title: "Your college study space, finally in one app.",
    body: "StudyShare brings notes, PYQs, videos, syllabus, notices, rooms and AI tools into one fast student workflow.",
    chips: ["Android launch", "College-first", "StudyShare"],
  },
  {
    start: 7,
    end: 18,
    kicker: "College pages",
    title: "Built around your college.",
    body: "KIET is the first fully functional page. Other college pages and material libraries are already staged to expand next.",
    chips: ["KIET live first", "More colleges soon", "Personalized resources"],
  },
  {
    start: 18,
    end: 31,
    kicker: "Resources",
    title: "Find the exact material before class starts.",
    body: "Search, filter, bookmark and download notes, PYQs, videos and syllabus items from the app home flow.",
    chips: ["Notes", "PYQs", "Videos", "Syllabus"],
  },
  {
    start: 31,
    end: 43,
    kicker: "Departments",
    title: "Follow departments. Receive notice alerts.",
    body: "The notices screen keeps college updates organized, while rooms keep class discussions and saved posts in one place.",
    chips: ["Department follows", "Notice notifications", "Rooms"],
    accent: C.orange,
  },
  {
    start: 43,
    end: 55,
    kicker: "Attendance",
    title: "Know your attendance risk early.",
    body: "For KIET, sync ERP to see overall and subject-wise attendance, day-wise records, low-attendance risk and calendar reminders.",
    chips: ["KIET ERP sync", "Subject-wise %", "Calendar reminders"],
  },
  {
    start: 55,
    end: 68,
    kicker: "AI Studio",
    title: "Turn resources into study mode.",
    body: "AI summaries, quizzes, flashcards and Study Chat work directly from a PDF or YouTube resource, with OCR controls when needed.",
    chips: ["Summary", "Quiz", "Cards", "Chat"],
  },
  {
    start: 68,
    end: 78,
    kicker: "Premium",
    title: "Upgrade only when you need more.",
    body: "Premium adds offline PDF downloads, one-year room validity, a profile badge and 10x monthly AI credits.",
    chips: ["Rs 49/month", "Rs 149/quarter", "AI top-ups from Rs 10"],
    accent: C.gold,
  },
  {
    start: 78,
    end: 85,
    kicker: "Personalization",
    title: "Dark by default. Light mode when you need it.",
    body: "The app keeps its floating study clock and animated sun-moon theme transition across modes.",
    chips: ["Light mode", "Floating clock", "Theme animation"],
  },
  {
    start: 85,
    end: 92.2,
    kicker: "Download",
    title: "Visit studyshare.in and download the Android APK.",
    body: "StudyShare is currently available on Android.",
    chips: ["studyshare.in", "Android APK", "Install and choose KIET"],
  },
];

const LaunchBackground: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const drift = progress(frame, fps, 0, 96, Easing.linear);
  const sweep = interpolate(Math.sin(frame / 46), [-1, 1], [-26, 26]);

  return (
    <AbsoluteFill
      style={{
        background: "linear-gradient(180deg, #02040A 0%, #050814 48%, #000 100%)",
        overflow: "hidden",
      }}
    >
      <div
        style={{
          position: "absolute",
          inset: -160,
          opacity: 0.17,
          backgroundImage:
            "linear-gradient(rgba(59,130,246,0.22) 1px, transparent 1px), linear-gradient(90deg, rgba(59,130,246,0.17) 1px, transparent 1px)",
          backgroundSize: "92px 92px",
          transform: `translateY(${px(-210 * drift)}) rotate(-7deg)`,
        }}
      />
      <div
        style={{
          position: "absolute",
          left: -260,
          top: 92,
          width: 2480,
          height: 280,
          opacity: 0.45,
          background:
            "linear-gradient(102deg, transparent 0%, rgba(37,99,235,0.28) 36%, rgba(249,115,22,0.12) 58%, transparent 82%)",
          transform: `translateX(${px(-170 + drift * 360)}) rotate(${sweep * 0.08}deg)`,
          filter: "blur(24px)",
        }}
      />
      <div
        style={{
          position: "absolute",
          inset: 0,
          background:
            "linear-gradient(90deg, rgba(0,0,0,0.42) 0%, rgba(0,0,0,0.1) 48%, rgba(0,0,0,0.54) 100%), linear-gradient(180deg, rgba(0,0,0,0) 0%, rgba(0,0,0,0.7) 100%)",
        }}
      />
    </AbsoluteFill>
  );
};

const CopyBlock: React.FC<{ scene: CopyScene }> = ({ scene }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const opacity = fadeBetween(frame, fps, scene.start, scene.end, 0.36);
  const local = frame - sf(scene.start, fps);
  const enter = spring({
    frame: local,
    fps,
    config: { damping: 200 },
    durationInFrames: 24,
  });
  const exitLift = interpolate(
    frame,
    [sf(scene.end - 0.55, fps), sf(scene.end, fps)],
    [0, -22],
    clamp,
  );
  const y = interpolate(enter, [0, 1], [34, 0], clamp) + exitLift;
  const scale = interpolate(enter, [0, 1], [0.97, 1], clamp);
  const accent = scene.accent ?? C.blueLight;

  return (
    <div
      style={{
        position: "absolute",
        left: 92,
        top: scene.start < 7 ? 160 : 178,
        width: 770,
        opacity,
        transform: `translateY(${px(y)}) scale(${scale})`,
        transformOrigin: "left center",
        ...baseText,
      }}
    >
      <div
        style={{
          display: "inline-flex",
          alignItems: "center",
          gap: 10,
          padding: "10px 15px",
          borderRadius: 999,
          background: `${accent}1F`,
          border: `1px solid ${accent}5C`,
          color: accent,
          fontSize: 23,
          lineHeight: 1,
          fontWeight: 800,
        }}
      >
        <Sparkles size={22} />
        {scene.kicker}
      </div>
      <div
        style={{
          marginTop: 24,
          maxWidth: scene.start < 7 ? 850 : 720,
          fontSize: scene.start < 7 ? 71 : 59,
          lineHeight: 1.03,
          fontWeight: 800,
          color: C.text,
        }}
      >
        {scene.title}
      </div>
      <div
        style={{
          marginTop: 20,
          width: 690,
          color: C.sub,
          fontSize: 28,
          lineHeight: 1.36,
          fontWeight: 500,
        }}
      >
        {scene.body}
      </div>
      <div style={{ marginTop: 28, display: "flex", flexWrap: "wrap", gap: 12 }}>
        {scene.chips.map((chip, index) => {
          const chipIn = spring({
            frame: local - 9 - index * 4,
            fps,
            config: { damping: 200 },
            durationInFrames: 18,
          });
          return (
            <div
              key={chip}
              style={{
                opacity: chipIn,
                transform: `translateY(${px(interpolate(chipIn, [0, 1], [14, 0], clamp))})`,
                padding: "11px 15px",
                borderRadius: 999,
                background: "rgba(255,255,255,0.075)",
                border: "1px solid rgba(255,255,255,0.13)",
                color: C.text,
                fontSize: 21,
                fontWeight: 750,
              }}
            >
              {chip}
            </div>
          );
        })}
      </div>
    </div>
  );
};

const PhoneStage: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const intro = progress(frame, fps, 0, 1.15, Easing.out(Easing.cubic));
  const outro = interpolate(frame, [sf(91.2, fps), sf(93, fps)], [1, 0], clamp);
  const x = interpolate(
    frame,
    [
      sf(0, fps),
      sf(7, fps),
      sf(18, fps),
      sf(31, fps),
      sf(43, fps),
      sf(55, fps),
      sf(68, fps),
      sf(78, fps),
      sf(85, fps),
      sf(92, fps),
    ],
    [44, 44, 22, -18, 36, -54, 24, 56, 28, 28],
    clamp,
  );
  const y = interpolate(
    frame,
    [
      sf(0, fps),
      sf(18, fps),
      sf(31, fps),
      sf(43, fps),
      sf(55, fps),
      sf(68, fps),
      sf(85, fps),
      sf(92, fps),
    ],
    [62, 58, 68, 55, 48, 58, 62, 62],
    clamp,
  );
  const scale = interpolate(
    frame,
    [
      sf(0, fps),
      sf(1.2, fps),
      sf(18, fps),
      sf(31, fps),
      sf(43, fps),
      sf(55, fps),
      sf(68, fps),
      sf(78, fps),
      sf(85, fps),
      sf(92, fps),
    ],
    [0.83, 0.94, 0.985, 1, 1.015, 1.055, 1, 1.01, 0.98, 0.98],
    clamp,
  );
  const tilt = interpolate(Math.sin(frame / 68), [-1, 1], [-1.1, 1.1]);

  return (
    <div
      style={{
        position: "absolute",
        right: 190,
        top: 0,
        width: phone.w,
        height: phone.h,
        opacity: intro * outro,
        transform: `translate(${px(x)}, ${px(y)}) scale(${scale}) rotate(${tilt}deg)`,
        transformOrigin: "center top",
        filter: "drop-shadow(0 42px 76px rgba(0,0,0,0.68))",
      }}
    >
      <IphoneFrame>
        <PhoneContent />
      </IphoneFrame>
    </div>
  );
};

const IphoneFrame: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  return (
    <div
      style={{
        width: phone.w,
        height: phone.h,
        borderRadius: 70,
        background:
          "linear-gradient(145deg, #070707 0%, #111 38%, #030303 72%, #181818 100%)",
        padding: phone.pad,
        boxShadow:
          "inset 0 0 0 2px rgba(255,255,255,0.16), inset 0 0 0 8px rgba(255,255,255,0.045)",
        position: "relative",
      }}
    >
      <div
        style={{
          width: "100%",
          height: "100%",
          borderRadius: 53,
          overflow: "hidden",
          position: "relative",
          background: "#000",
        }}
      >
        {children}
      </div>
      <div
        style={{
          position: "absolute",
          top: 29,
          left: "50%",
          width: 124,
          height: 36,
          marginLeft: -62,
          borderRadius: 999,
          background: "#050505",
          border: "1px solid rgba(255,255,255,0.08)",
        }}
      />
      <div
        style={{
          position: "absolute",
          inset: 9,
          borderRadius: 64,
          border: "1px solid rgba(255,255,255,0.08)",
          pointerEvents: "none",
        }}
      />
    </div>
  );
};

const PhoneContent: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const screens = [
    { start: 0, end: 18.6, node: <CollegeSelectionScreen start={0} /> },
    { start: 17.3, end: 31.7, node: <ResourceWalkthroughScreen start={17.3} /> },
    { start: 30.4, end: 43.7, node: <NoticesRoomsScreen start={30.4} /> },
    { start: 42.3, end: 55.6, node: <AttendanceScreen start={42.3} /> },
    { start: 54.5, end: 68.8, node: <AiStudioScreen start={54.5} /> },
    { start: 67.7, end: 78.9, node: <ProfilePremiumScreen start={67.7} /> },
    { start: 77.8, end: 85.8, node: <ThemeClockScreen start={77.8} /> },
    { start: 84.7, end: 92.8, node: <DownloadScreen start={84.7} /> },
  ];

  return (
    <AbsoluteFill style={{ background: "#000", ...baseText }}>
      {screens.map((screen) => (
        <AbsoluteFill
          key={`${screen.start}-${screen.end}`}
          style={{ opacity: fadeBetween(frame, fps, screen.start, screen.end, 0.46) }}
        >
          {screen.node}
        </AbsoluteFill>
      ))}
    </AbsoluteFill>
  );
};

const StatusBar: React.FC<{ light?: boolean }> = ({ light }) => (
  <div
    style={{
      height: 54,
      padding: "16px 22px 0",
      display: "flex",
      alignItems: "flex-start",
      justifyContent: "space-between",
      color: light ? "#0F172A" : "#fff",
      fontFamily,
      fontSize: 16,
      fontWeight: 750,
    }}
  >
    <div>10:30</div>
    <div style={{ display: "flex", gap: 7, alignItems: "center" }}>
      <div style={{ display: "flex", gap: 3, height: 17, alignItems: "flex-end" }}>
        {[6, 9, 13, 17].map((h, i) => (
          <div
            key={h}
            style={{
              width: 4,
              height: h,
              borderRadius: 3,
              background: i === 0 ? (light ? "#64748B" : "#A1A1AA") : light ? "#0F172A" : "#fff",
            }}
          />
        ))}
      </div>
      <div
        style={{
          width: 25,
          height: 17,
          borderRadius: 5,
          border: `2px solid ${light ? "#0F172A" : "#fff"}`,
          position: "relative",
        }}
      >
        <div
          style={{
            position: "absolute",
            right: -5,
            top: 4,
            width: 3,
            height: 7,
            borderRadius: 2,
            background: light ? "#0F172A" : "#fff",
          }}
        />
      </div>
    </div>
  </div>
);

const IconBubble: React.FC<{
  icon: LucideIcon;
  color?: string;
  size?: number;
  fill?: string;
}> = ({ icon: Icon, color = C.blueLight, size = 48, fill }) => (
  <div
    style={{
      width: size,
      height: size,
      borderRadius: Math.round(size * 0.32),
      background: fill ?? `${color}22`,
      border: `1px solid ${color}42`,
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      flex: "none",
    }}
  >
    <Icon size={Math.round(size * 0.48)} color={color} strokeWidth={2.55} />
  </div>
);

const Pill: React.FC<{ label: string; active?: boolean; color?: string }> = ({
  label,
  active,
  color = C.blueLight,
}) => (
  <div
    style={{
      borderRadius: 999,
      padding: "7px 10px",
      background: active ? `${color}24` : "rgba(255,255,255,0.07)",
      border: `1px solid ${active ? `${color}5E` : "rgba(255,255,255,0.11)"}`,
      color: active ? color : C.sub,
      fontSize: 12,
      fontWeight: 800,
      whiteSpace: "nowrap",
    }}
  >
    {label}
  </div>
);

const BottomNav: React.FC<{
  active: "home" | "rooms" | "notices" | "profile";
  light?: boolean;
}> = ({ active, light }) => {
  const items: Array<{ id: "home" | "rooms" | "notices" | "profile"; label: string; icon: LucideIcon }> = [
    { id: "home", label: "Home", icon: Home },
    { id: "rooms", label: "Rooms", icon: MessageSquare },
    { id: "notices", label: "Notices", icon: Bell },
    { id: "profile", label: "Profile", icon: Users },
  ];
  const bg = light ? "rgba(255,255,255,0.9)" : "rgba(23,23,23,0.94)";
  return (
    <div
      style={{
        position: "absolute",
        left: 16,
        right: 16,
        bottom: 16,
        height: 72,
        borderRadius: 36,
        background: bg,
        border: `1px solid ${light ? "rgba(15,23,42,0.08)" : "rgba(255,255,255,0.12)"}`,
        display: "flex",
        alignItems: "center",
        justifyContent: "space-around",
        boxShadow: light ? "0 -12px 34px rgba(15,23,42,0.08)" : "0 -16px 40px rgba(0,0,0,0.38)",
      }}
    >
      {items.map(({ id, label, icon: Icon }, index) => {
        const isActive = active === id;
        return (
          <div
            key={id}
            style={{
              width: index === 1 ? 70 : 78,
              display: "flex",
              flexDirection: "column",
              alignItems: "center",
              gap: 4,
              color: isActive ? C.blueLight : light ? "#64748B" : "#A7AAB3",
              fontFamily,
              fontSize: 12,
              fontWeight: 750,
            }}
          >
            <Icon size={22} strokeWidth={2.4} />
            {label}
          </div>
        );
      })}
      <div
        style={{
          position: "absolute",
          top: -30,
          left: "50%",
          marginLeft: -36,
          width: 72,
          height: 72,
          borderRadius: 36,
          background: C.blue,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          boxShadow: "0 16px 34px rgba(37,99,235,0.36)",
        }}
      >
        <Plus size={32} color="#fff" strokeWidth={2.5} />
      </div>
    </div>
  );
};

const CollegeSelectionScreen: React.FC<{ start: number }> = ({ start }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const local = frame - sf(start, fps);
  const listShift = interpolate(
    local,
    [sf(8, fps), sf(15, fps)],
    [0, -22],
    { ...clamp, easing: Easing.inOut(Easing.cubic) },
  );
  const kiHighlight = interpolate(Math.sin(Math.max(0, local - sf(6, fps)) / 14), [-1, 1], [0.22, 0.42]);

  return (
    <AbsoluteFill style={{ background: "#000", ...baseText }}>
      <StatusBar />
      <div style={{ padding: "36px 22px 0" }}>
        <div
          style={{
            width: 60,
            height: 60,
            borderRadius: 18,
            background: C.blue,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            margin: "8px auto 18px",
            boxShadow: "0 18px 36px rgba(37,99,235,0.28)",
          }}
        >
          <GraduationCap size={33} color="#fff" strokeWidth={2.4} />
        </div>
        <div style={{ textAlign: "center", fontSize: 28, fontWeight: 800 }}>Select Your College</div>
        <div
          style={{
            margin: "8px auto 0",
            color: C.sub,
            fontSize: 14,
            lineHeight: 1.35,
            fontWeight: 600,
            textAlign: "center",
            width: 320,
          }}
        >
          Choose your institution to access personalized resources
        </div>
        <div
          style={{
            marginTop: 22,
            height: 48,
            borderRadius: 16,
            background: "#111827",
            border: "1px solid rgba(255,255,255,0.1)",
            display: "flex",
            alignItems: "center",
            gap: 10,
            padding: "0 14px",
            color: C.muted,
            fontSize: 14,
            fontWeight: 650,
          }}
        >
          <Search size={19} color={C.muted} />
          Search colleges...
        </div>
        <div style={{ marginTop: 20, height: 540, overflow: "hidden" }}>
          <div style={{ transform: `translateY(${px(listShift)})` }}>
            <CollegeRow
              title="KIET Group of Institutions"
              subtitle="Ghaziabad, Uttar Pradesh"
              status="Fully functional"
              active
              glow={kiHighlight}
            />
            <CollegeRow title="IIIT Bhagalpur" subtitle="Materials coming soon" status="Coming soon" />
            <CollegeRow title="ABES Engineering College" subtitle="Materials coming soon" status="Coming soon" />
            <CollegeRow title="Delhi University" subtitle="Materials coming soon" status="Coming soon" />
            <CollegeRow title="IIT Delhi" subtitle="Materials coming soon" status="Coming soon" />
            <CollegeRow title="VIT Vellore" subtitle="Materials coming soon" status="Coming soon" />
          </div>
        </div>
      </div>
    </AbsoluteFill>
  );
};

const CollegeRow: React.FC<{
  title: string;
  subtitle: string;
  status: string;
  active?: boolean;
  glow?: number;
}> = ({ title, subtitle, status, active, glow = 0.16 }) => (
  <div
    style={{
      minHeight: 82,
      borderRadius: 22,
      background: active ? `rgba(37,99,235,${glow})` : "#121722",
      border: `1px solid ${active ? "rgba(59,130,246,0.58)" : C.border}`,
      marginBottom: 13,
      padding: "14px 15px",
      display: "flex",
      alignItems: "center",
      gap: 13,
    }}
  >
    <IconBubble icon={GraduationCap} color={active ? C.blueLight : "#8B94A5"} size={46} />
    <div style={{ flex: 1, minWidth: 0 }}>
      <div style={{ fontSize: 16, lineHeight: 1.18, fontWeight: 800 }}>{title}</div>
      <div style={{ marginTop: 5, color: C.sub, fontSize: 12, fontWeight: 650 }}>{subtitle}</div>
    </div>
    <Pill label={status} active={active} color={active ? C.blueLight : C.muted} />
  </div>
);

const ScreenshotScreen: React.FC<{
  src: string;
  scale?: number;
  y?: number;
  dim?: number;
}> = ({ src, scale = 1, y = 0, dim = 0 }) => (
  <AbsoluteFill style={{ background: "#000", overflow: "hidden" }}>
    <Img
      src={staticFile(src)}
      style={{
        position: "absolute",
        inset: 0,
        width: "100%",
        height: "100%",
        objectFit: "cover",
        transform: `scale(${scale}) translateY(${px(y)})`,
      }}
    />
    {dim ? <AbsoluteFill style={{ background: `rgba(0,0,0,${dim})` }} /> : null}
  </AbsoluteFill>
);

const ResourceWalkthroughScreen: React.FC<{ start: number }> = ({ start }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const local = frame - sf(start, fps);
  const feedOpacity = interpolate(local, [sf(0, fps), sf(7.4, fps), sf(8.2, fps)], [1, 1, 0], clamp);
  const syllabusOpacity = interpolate(local, [sf(7.3, fps), sf(8.2, fps), sf(14, fps)], [0, 1, 1], clamp);
  const zoom = interpolate(local, [sf(1.4, fps), sf(5.8, fps), sf(10.5, fps)], [1.01, 1.055, 1.02], clamp);

  return (
    <AbsoluteFill style={{ background: "#000" }}>
      <AbsoluteFill style={{ opacity: feedOpacity }}>
        <ScreenshotScreen src="assets/screens/resources-feed.png" scale={zoom} y={-8} />
        <SpotlightBox top={130} left={18} width={344} height={58} label="Search + filters" />
        <SpotlightBox top={296} left={22} width={346} height={122} label="Notes, PYQs, downloads" />
        <FloatingClockOverlay start={start + 2.3} />
      </AbsoluteFill>
      <AbsoluteFill style={{ opacity: syllabusOpacity }}>
        <ScreenshotScreen src="assets/screens/syllabus-departments.png" scale={1.025} y={-4} />
        <SpotlightBox top={188} left={30} width={330} height={238} label="Syllabus by department" />
        <FloatingClockOverlay start={start + 8.6} />
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

const SpotlightBox: React.FC<{
  top: number;
  left: number;
  width: number;
  height: number;
  label: string;
}> = ({ top, left, width, height, label }) => {
  const frame = useCurrentFrame();
  const pulse = interpolate(Math.sin(frame / 10), [-1, 1], [0.28, 0.58]);
  return (
    <div
      style={{
        position: "absolute",
        top,
        left,
        width,
        height,
        borderRadius: 18,
        border: `2px solid rgba(59,130,246,${pulse})`,
        boxShadow: `0 0 0 999px rgba(0,0,0,0.13), 0 0 28px rgba(59,130,246,${pulse * 0.5})`,
      }}
    >
      <div
        style={{
          position: "absolute",
          left: 10,
          top: -24,
          borderRadius: 999,
          padding: "4px 8px",
          background: "rgba(37,99,235,0.95)",
          color: "#fff",
          fontFamily,
          fontSize: 11,
          fontWeight: 800,
        }}
      >
        {label}
      </div>
    </div>
  );
};

const NoticesRoomsScreen: React.FC<{ start: number }> = ({ start }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const local = frame - sf(start, fps);
  const departments = progress(local, fps, 4.4, 6.1);
  const toast = spring({
    frame: local - sf(1.2, fps),
    fps,
    config: { damping: 180 },
    durationInFrames: 22,
  });
  const rooms = progress(local, fps, 8.6, 10.8);

  return (
    <AbsoluteFill style={{ background: "#000", ...baseText }}>
      <StatusBar />
      <div style={{ padding: "42px 18px 0" }}>
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
          <div>
            <div style={{ fontSize: 23, fontWeight: 800 }}>Notices</div>
            <div style={{ marginTop: 5, color: C.muted, fontSize: 12, fontWeight: 650 }}>
              Latest updates from your departments
            </div>
          </div>
          <IconBubble icon={CalendarCheck} size={42} color={C.blueLight} />
        </div>
        <div
          style={{
            marginTop: 16,
            height: 46,
            borderRadius: 16,
            background: "rgba(255,255,255,0.07)",
            border: "1px solid rgba(255,255,255,0.1)",
            display: "flex",
            alignItems: "center",
            gap: 10,
            padding: "0 13px",
            color: C.muted,
            fontSize: 13,
            fontWeight: 650,
          }}
        >
          <Search size={18} />
          Search notices...
        </div>
        <div
          style={{
            marginTop: 14,
            height: 42,
            display: "grid",
            gridTemplateColumns: "1fr 1fr",
            borderBottom: "1px solid rgba(255,255,255,0.08)",
          }}
        >
          <TabLabel label="Latest Updates" active={departments < 0.5} />
          <TabLabel label="Departments" active={departments >= 0.5} />
        </div>
        <div style={{ marginTop: 15, transform: `translateX(${px(-departments * 398)})`, display: "flex", gap: 18, width: 800 }}>
          <div style={{ width: 380, flex: "none" }}>
            <NoticeCard title="Exam form deadline" dept="General" body="Complete registration before Friday." />
            <NoticeCard title="AI tools workshop" dept="CSE" body="Auditorium, 3 PM today." />
            <NoticeCard title="Question bank updated" dept="ECE" body="New PYQs added for semester 1." />
          </div>
          <div style={{ width: 380, flex: "none" }}>
            <DepartmentCard name="Computer Science" code="CSE" followed />
            <DepartmentCard name="Information Technology" code="IT" followed />
            <DepartmentCard name="Electronics" code="ECE" />
          </div>
        </div>
      </div>
      <div
        style={{
          position: "absolute",
          top: 164,
          left: 30,
          right: 30,
          borderRadius: 20,
          background: "rgba(23,27,36,0.96)",
          border: "1px solid rgba(255,255,255,0.13)",
          padding: "12px 14px",
          display: "flex",
          alignItems: "center",
          gap: 11,
          opacity: toast,
          transform: `translateY(${px(interpolate(toast, [0, 1], [-28, 0], clamp))})`,
          boxShadow: "0 18px 36px rgba(0,0,0,0.34)",
        }}
      >
        <IconBubble icon={BellRing} color={C.orange} size={42} />
        <div>
          <div style={{ fontSize: 15, fontWeight: 800 }}>New CSE notice</div>
          <div style={{ marginTop: 3, color: C.sub, fontSize: 12, fontWeight: 650 }}>
            Notification from a followed department
          </div>
        </div>
      </div>
      <div
        style={{
          position: "absolute",
          left: 20,
          right: 20,
          bottom: 104,
          transform: `translateX(${px((1 - rooms) * 430)})`,
          opacity: rooms,
        }}
      >
        <RoomStrip />
      </div>
      <BottomNav active={rooms > 0.45 ? "rooms" : "notices"} />
    </AbsoluteFill>
  );
};

const TabLabel: React.FC<{ label: string; active: boolean }> = ({ label, active }) => (
  <div
    style={{
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      color: active ? C.blueLight : C.muted,
      fontSize: 13,
      fontWeight: 800,
      borderBottom: active ? `2px solid ${C.blueLight}` : "2px solid transparent",
    }}
  >
    {label}
  </div>
);

const NoticeCard: React.FC<{ title: string; dept: string; body: string }> = ({
  title,
  dept,
  body,
}) => (
  <div
    style={{
      borderRadius: 24,
      background: "#0F1117",
      border: "1px solid rgba(255,255,255,0.1)",
      padding: 15,
      marginBottom: 13,
    }}
  >
    <div style={{ display: "flex", alignItems: "center", gap: 11 }}>
      <IconBubble icon={Bell} color={C.orange} size={42} />
      <div style={{ flex: 1 }}>
        <div style={{ fontSize: 16, fontWeight: 800 }}>{title}</div>
        <div style={{ marginTop: 4, color: C.sub, fontSize: 12, fontWeight: 650 }}>{dept} notice</div>
      </div>
    </div>
    <div style={{ marginTop: 10, color: C.sub, fontSize: 13, lineHeight: 1.28, fontWeight: 600 }}>{body}</div>
  </div>
);

const DepartmentCard: React.FC<{ name: string; code: string; followed?: boolean }> = ({
  name,
  code,
  followed,
}) => (
  <div
    style={{
      height: 78,
      borderRadius: 22,
      background: "#171B24",
      border: `1px solid ${followed ? "rgba(59,130,246,0.42)" : C.border}`,
      marginBottom: 13,
      padding: "12px 13px",
      display: "flex",
      alignItems: "center",
      gap: 12,
    }}
  >
    <IconBubble icon={Users} color={followed ? C.blueLight : "#8B94A5"} size={42} />
    <div style={{ flex: 1, minWidth: 0 }}>
      <div style={{ fontSize: 15, fontWeight: 800 }}>{code}</div>
      <div style={{ marginTop: 4, color: C.sub, fontSize: 12, fontWeight: 650 }}>{name}</div>
    </div>
    <Pill label={followed ? "Following" : "Follow"} active={followed} />
  </div>
);

const RoomStrip: React.FC = () => (
  <div
    style={{
      borderRadius: 24,
      background: "linear-gradient(140deg, rgba(37,99,235,0.18), rgba(23,27,36,0.96))",
      border: "1px solid rgba(59,130,246,0.28)",
      padding: 15,
    }}
  >
    <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
      <IconBubble icon={MessageSquare} color={C.blueLight} size={45} />
      <div>
        <div style={{ fontSize: 17, fontWeight: 800 }}>CSE Sem 1 Doubts</div>
        <div style={{ marginTop: 4, color: C.sub, fontSize: 12, fontWeight: 650 }}>
          Saved posts, room codes and class discussions
        </div>
      </div>
    </div>
  </div>
);

const AttendanceScreen: React.FC<{ start: number }> = ({ start }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const local = frame - sf(start, fps);
  const ring = progress(local, fps, 1.2, 4.4);
  const riskIn = spring({
    frame: local - sf(4.8, fps),
    fps,
    config: { damping: 190 },
    durationInFrames: 24,
  });
  const scheduleIn = spring({
    frame: local - sf(7.2, fps),
    fps,
    config: { damping: 190 },
    durationInFrames: 24,
  });

  return (
    <AbsoluteFill style={{ background: "#000", ...baseText }}>
      <StatusBar />
      <div style={{ padding: "42px 18px 0" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 11 }}>
          <CalendarCheck size={30} color={C.blueLight} />
          <div>
            <div style={{ fontSize: 25, fontWeight: 800 }}>Attendance</div>
            <div style={{ marginTop: 4, color: C.sub, fontSize: 12, fontWeight: 700 }}>
              KIET ERP synced from CyberVidya
            </div>
          </div>
        </div>
        <div
          style={{
            marginTop: 20,
            borderRadius: 26,
            background: "#101827",
            border: "1px solid rgba(59,130,246,0.26)",
            padding: 18,
            display: "flex",
            alignItems: "center",
            gap: 18,
          }}
        >
          <div
            style={{
              width: 124,
              height: 124,
              borderRadius: "50%",
              background: `conic-gradient(${C.blueLight} ${ring * 282.6}deg, #242B38 0deg)`,
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
            }}
          >
            <div
              style={{
                width: 100,
                height: 100,
                borderRadius: "50%",
                background: "#101827",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                flexDirection: "column",
              }}
            >
              <div style={{ fontSize: 30, fontWeight: 800 }}>78.5%</div>
              <div style={{ marginTop: 2, color: C.sub, fontSize: 11, fontWeight: 800 }}>Overall</div>
            </div>
          </div>
          <div style={{ flex: 1 }}>
            <div style={{ fontSize: 18, fontWeight: 800 }}>Current standing</div>
            <div style={{ marginTop: 7, color: C.sub, fontSize: 12, lineHeight: 1.35, fontWeight: 650 }}>
              Actual attendance, projected risk and last sync stay visible.
            </div>
            <div style={{ marginTop: 11, display: "flex", flexWrap: "wrap", gap: 7 }}>
              <Pill label="Actual" active />
              <Pill label="Projected" />
              <Pill label="Low subjects" color={C.orange} />
            </div>
          </div>
        </div>
        <div
          style={{
            marginTop: 16,
            opacity: riskIn,
            transform: `translateY(${px(interpolate(riskIn, [0, 1], [28, 0], clamp))})`,
          }}
        >
          <AttendanceSubject name="Engineering Chemistry" percent="71%" risky />
          <AttendanceSubject name="Data Structures" percent="84%" />
          <AttendanceSubject name="Mathematics" percent="80%" />
        </div>
        <div
          style={{
            marginTop: 15,
            borderRadius: 23,
            background: "rgba(5,150,105,0.11)",
            border: "1px solid rgba(5,150,105,0.34)",
            padding: 15,
            display: "flex",
            alignItems: "center",
            gap: 12,
            opacity: scheduleIn,
            transform: `translateY(${px(interpolate(scheduleIn, [0, 1], [30, 0], clamp))})`,
          }}
        >
          <IconBubble icon={Clock} color="#34D399" size={44} />
          <div>
            <div style={{ fontSize: 16, fontWeight: 800 }}>Upcoming classes</div>
            <div style={{ color: C.sub, marginTop: 4, fontSize: 12, fontWeight: 650 }}>
              Add class reminders to calendar
            </div>
          </div>
        </div>
      </div>
      <BottomNav active="home" />
    </AbsoluteFill>
  );
};

const AttendanceSubject: React.FC<{ name: string; percent: string; risky?: boolean }> = ({
  name,
  percent,
  risky,
}) => (
  <div
    style={{
      height: 68,
      borderRadius: 20,
      background: "#171B24",
      border: `1px solid ${risky ? "rgba(249,115,22,0.52)" : C.border}`,
      marginBottom: 11,
      padding: "0 13px",
      display: "flex",
      alignItems: "center",
      gap: 11,
    }}
  >
    <IconBubble icon={risky ? AlertTriangle : BarChart3} color={risky ? C.orange : C.blueLight} size={42} />
    <div style={{ flex: 1, minWidth: 0 }}>
      <div style={{ fontSize: 14, fontWeight: 800 }}>{name}</div>
      <div style={{ marginTop: 4, color: risky ? "#FDBA74" : C.sub, fontSize: 11, fontWeight: 750 }}>
        {risky ? "Low attendance risk" : "On track"}
      </div>
    </div>
    <div style={{ fontSize: 20, fontWeight: 800, color: risky ? C.orange : "#fff" }}>{percent}</div>
  </div>
);

const AiStudioScreen: React.FC<{ start: number }> = ({ start }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const local = frame - sf(start, fps);
  const sheet = spring({
    frame: local - sf(1.2, fps),
    fps,
    config: { damping: 185 },
    durationInFrames: 28,
  });
  const tabShift = progress(local, fps, 6.4, 9.8);

  return (
    <AbsoluteFill style={{ background: "#000", ...baseText }}>
      <ScreenshotScreen src="assets/screens/resources-feed.png" scale={1.025} dim={0.28} />
      <div
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          bottom: 0,
          height: 775,
          borderTopLeftRadius: 32,
          borderTopRightRadius: 32,
          background:
            "linear-gradient(180deg, rgba(10,17,32,0.95) 0%, rgba(4,8,16,0.98) 100%)",
          borderTop: "1.5px solid rgba(255,255,255,0.1)",
          padding: "13px 18px 0",
          transform: `translateY(${px((1 - sheet) * 560)})`,
          opacity: 0.18 + sheet * 0.82,
          boxShadow: "0 -24px 50px rgba(0,0,0,0.45)",
        }}
      >
        <div
          style={{
            width: 42,
            height: 4,
            borderRadius: 999,
            background: "rgba(255,255,255,0.28)",
            margin: "0 auto 16px",
          }}
        />
        <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
          <IconBubble icon={Bot} color={C.blueLight} size={46} />
          <div>
            <div style={{ fontSize: 23, fontWeight: 800 }}>AI Studio</div>
            <div style={{ marginTop: 3, color: C.sub, fontSize: 12, fontWeight: 650 }}>
              Resource-aware study tools
            </div>
          </div>
          <div style={{ marginLeft: "auto" }}>
            <IconBubble icon={Settings} color="#94A3B8" size={38} />
          </div>
        </div>
        <div
          style={{
            marginTop: 16,
            borderRadius: 22,
            background: "#111A2A",
            border: "1px solid #24324A",
            padding: 12,
          }}
        >
          <div style={{ display: "flex", alignItems: "center", gap: 9 }}>
            <Pill label="OCR auto" active />
            <Pill label="Force OCR" />
            <Pill label="PDF + YouTube" color={C.orange} />
          </div>
          <div
            style={{
              marginTop: 12,
              height: 50,
              borderRadius: 18,
              background: "#0B1220",
              border: "1px solid rgba(255,255,255,0.08)",
              display: "grid",
              gridTemplateColumns: "repeat(4, 1fr)",
              overflow: "hidden",
            }}
          >
            {[
              ["Summary", FileText],
              ["Quiz", Trophy],
              ["Cards", BadgeCheck],
              ["Chat", MessageSquare],
            ].map(([label, Icon], index) => {
              const active = Math.round(tabShift * 3) === index;
              const IconTyped = Icon as LucideIcon;
              return (
                <div
                  key={label as string}
                  style={{
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    flexDirection: "column",
                    gap: 3,
                    background: active ? "rgba(37,99,235,0.2)" : "transparent",
                    color: active ? C.blueLight : C.muted,
                    fontSize: 10,
                    fontWeight: 800,
                  }}
                >
                  <IconTyped size={16} />
                  {label as string}
                </div>
              );
            })}
          </div>
        </div>
        <div
          style={{
            marginTop: 18,
            borderRadius: 24,
            background: "#0B1220",
            border: "1px solid rgba(255,255,255,0.09)",
            padding: 16,
          }}
        >
          <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
            <Sparkles size={20} color={C.blueLight} />
            <div style={{ fontSize: 16, fontWeight: 800 }}>Generated from this resource</div>
          </div>
          <div style={{ marginTop: 12, color: C.sub, fontSize: 13, lineHeight: 1.42, fontWeight: 600 }}>
            Important concepts are summarized, converted into practice questions and ready for a Study Chat follow-up.
          </div>
          <div style={{ marginTop: 14, display: "grid", gridTemplateColumns: "1fr 1fr", gap: 10 }}>
            <AiResultTile icon={CheckCircle2} title="Key points" />
            <AiResultTile icon={Trophy} title="Practice quiz" />
          </div>
        </div>
      </div>
    </AbsoluteFill>
  );
};

const AiResultTile: React.FC<{ icon: LucideIcon; title: string }> = ({ icon: Icon, title }) => (
  <div
    style={{
      borderRadius: 17,
      background: "rgba(255,255,255,0.06)",
      border: "1px solid rgba(255,255,255,0.09)",
      padding: 11,
      display: "flex",
      alignItems: "center",
      gap: 9,
      color: C.sub,
      fontSize: 12,
      fontWeight: 800,
    }}
  >
    <Icon size={18} color={C.blueLight} />
    {title}
  </div>
);

const ProfilePremiumScreen: React.FC<{ start: number }> = ({ start }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const local = frame - sf(start, fps);
  const sheet = progress(local, fps, 4.7, 6.2);

  return (
    <AbsoluteFill style={{ background: "#000", ...baseText }}>
      <ScreenshotScreen src="assets/screens/profile-screen.png" scale={1.012} y={-4} />
      <ProfilePrivacyOverlay />
      <div
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          bottom: 0,
          height: 432,
          borderTopLeftRadius: 34,
          borderTopRightRadius: 34,
          background: "#0F172A",
          borderTop: "1px solid rgba(255,255,255,0.12)",
          padding: "22px 19px",
          transform: `translateY(${px((1 - sheet) * 340)})`,
          opacity: 0.22 + sheet * 0.78,
          boxShadow: "0 -28px 52px rgba(0,0,0,0.5)",
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
          <Crown size={25} color={C.gold} />
          <div style={{ fontSize: 23, fontWeight: 800 }}>StudyShare Premium</div>
        </div>
        <div style={{ marginTop: 8, color: C.sub, fontSize: 12.5, lineHeight: 1.35, fontWeight: 650 }}>
          Offline downloads, longer rooms and more AI credits.
        </div>
        <div style={{ marginTop: 15, display: "grid", gridTemplateColumns: "1fr 1fr", gap: 10 }}>
          <PlanCard title="Monthly" price="Rs 49" />
          <PlanCard title="Quarterly" price="Rs 149" badge="Best value" />
        </div>
        <PremiumBenefit icon={Download} text="Offline PDF downloads" />
        <PremiumBenefit icon={MessageSquare} text="One-year chat room validity" />
        <PremiumBenefit icon={BadgeCheck} text="Premium profile badge" />
        <PremiumBenefit icon={Zap} text="10x monthly AI credits; top-ups from Rs 10" />
      </div>
      <BottomNav active="profile" />
    </AbsoluteFill>
  );
};

const ProfilePrivacyOverlay: React.FC = () => (
  <div
    style={{
      position: "absolute",
      left: 21,
      right: 21,
      top: 78,
      height: 334,
      borderRadius: 30,
      background: "linear-gradient(180deg, #000 0%, #050812 100%)",
      border: "1px solid rgba(255,255,255,0.1)",
      paddingTop: 26,
      textAlign: "center",
      boxShadow: "0 22px 44px rgba(0,0,0,0.36)",
    }}
  >
    <div
      style={{
        width: 112,
        height: 112,
        borderRadius: 64,
        border: `5px solid ${C.gold}`,
        background: "#172033",
        margin: "0 auto",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        fontSize: 38,
        fontWeight: 800,
        color: C.gold,
      }}
    >
      HA
    </div>
    <div style={{ marginTop: 17, fontSize: 27, fontWeight: 800, display: "flex", alignItems: "center", justifyContent: "center", gap: 8 }}>
      harsh attri
      <BadgeCheck size={23} color={C.gold} fill={C.gold} />
    </div>
    <div style={{ marginTop: 7, color: C.sub, fontSize: 14, fontWeight: 700 }}>@harshattri</div>
    <div style={{ marginTop: 11, display: "flex", justifyContent: "center", gap: 8 }}>
      <Pill label="KIET" active />
      <Pill label="CSE/CS" />
      <Pill label="Sem 1" />
    </div>
  </div>
);

const PlanCard: React.FC<{ title: string; price: string; badge?: string }> = ({
  title,
  price,
  badge,
}) => (
  <div
    style={{
      borderRadius: 18,
      border: `1px solid ${badge ? C.orange : C.border}`,
      background: badge ? "rgba(249,115,22,0.12)" : "#151D2B",
      padding: 13,
    }}
  >
    <div style={{ color: C.sub, fontSize: 12, fontWeight: 800 }}>{title}</div>
    <div style={{ fontSize: 23, fontWeight: 800, marginTop: 5 }}>{price}</div>
    {badge ? <div style={{ marginTop: 7, color: C.orange, fontSize: 11, fontWeight: 800 }}>{badge}</div> : null}
  </div>
);

const PremiumBenefit: React.FC<{ icon: LucideIcon; text: string }> = ({ icon: Icon, text }) => (
  <div
    style={{
      display: "flex",
      alignItems: "center",
      gap: 10,
      marginTop: 12,
      color: C.sub,
      fontSize: 13,
      fontWeight: 750,
    }}
  >
    <CheckCircle2 size={18} color="#34D399" />
    <Icon size={18} color={C.blueLight} />
    {text}
  </div>
);

const ThemeClockScreen: React.FC<{ start: number }> = ({ start }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const local = frame - sf(start, fps);
  const theme = progress(local, fps, 0.7, 2.5);
  const label = spring({
    frame: local - sf(2.6, fps),
    fps,
    config: { damping: 200 },
    durationInFrames: 22,
  });

  return (
    <AbsoluteFill style={{ background: "#000", ...baseText }}>
      <AbsoluteFill style={{ opacity: 1 - theme }}>
        <ScreenshotScreen src="assets/screens/resources-feed.png" scale={1.025} />
      </AbsoluteFill>
      <AbsoluteFill style={{ opacity: theme }}>
        <LightModeResources />
      </AbsoluteFill>
      <ThemeTransitionOverlay value={theme} />
      <FloatingClockOverlay start={start + 0.1} forceLight={theme > 0.58} />
      <div
        style={{
          position: "absolute",
          left: 20,
          right: 20,
          top: 660,
          borderRadius: 22,
          background: theme > 0.56 ? "rgba(255,255,255,0.9)" : "rgba(23,27,36,0.94)",
          border: `1px solid ${theme > 0.56 ? "rgba(15,23,42,0.08)" : "rgba(255,255,255,0.12)"}`,
          padding: "14px 16px",
          display: "flex",
          alignItems: "center",
          gap: 11,
          color: theme > 0.56 ? "#0F172A" : C.text,
          opacity: label,
          transform: `translateY(${px(interpolate(label, [0, 1], [22, 0], clamp))})`,
          boxShadow: theme > 0.56 ? "0 18px 34px rgba(15,23,42,0.1)" : "0 18px 34px rgba(0,0,0,0.28)",
        }}
      >
        <IconBubble icon={theme > 0.56 ? Sun : Moon} color={theme > 0.56 ? C.orange : C.blueLight} size={42} />
        <div>
          <div style={{ fontSize: 16, fontWeight: 800 }}>Light mode is available</div>
          <div style={{ marginTop: 3, color: theme > 0.56 ? "#475569" : C.sub, fontSize: 12, fontWeight: 650 }}>
            Same StudyShare controls, brighter surface.
          </div>
        </div>
      </div>
    </AbsoluteFill>
  );
};

const ThemeTransitionOverlay: React.FC<{ value: number }> = ({ value }) => {
  const moonY = interpolate(value, [0, 1], [230, 900], clamp);
  const sunY = interpolate(value, [0, 1], [920, 210], clamp);
  const sky = interpolate(value, [0, 1], [0.04, 0.46], clamp);
  const stars = interpolate(value, [0, 0.35], [0.35, 0], clamp);

  return (
    <AbsoluteFill style={{ pointerEvents: "none", overflow: "hidden" }}>
      <AbsoluteFill
        style={{
          opacity: sky,
          background: "linear-gradient(180deg, rgba(147,197,253,0.52), rgba(255,255,255,0.16) 74%)",
        }}
      />
      <div
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          top: "70%",
          height: 2,
          background: "rgba(255,255,255,0.4)",
          opacity: 0.22 + value * 0.35,
        }}
      />
      {[48, 126, 216, 302].map((left, index) => (
        <div
          key={left}
          style={{
            position: "absolute",
            left,
            top: 92 + index * 42,
            width: 3,
            height: 3,
            borderRadius: "50%",
            background: "#fff",
            opacity: stars,
          }}
        />
      ))}
      <div
        style={{
          position: "absolute",
          right: 62,
          top: moonY,
          width: 70,
          height: 70,
          borderRadius: "50%",
          background: "#CBD5E1",
          boxShadow: "0 0 30px rgba(203,213,225,0.5)",
        }}
      >
        <div
          style={{
            position: "absolute",
            right: -7,
            top: -2,
            width: 70,
            height: 70,
            borderRadius: "50%",
            background: "#02040A",
          }}
        />
      </div>
      <div
        style={{
          position: "absolute",
          left: 58,
          top: sunY,
          width: 78,
          height: 78,
          borderRadius: "50%",
          background: "#FBBF24",
          boxShadow: "0 0 54px rgba(251,191,36,0.55)",
        }}
      />
    </AbsoluteFill>
  );
};

const LightModeResources: React.FC = () => (
  <AbsoluteFill style={{ background: "#F8FAFC", color: "#0F172A", ...baseText }}>
    <StatusBar light />
    <div style={{ padding: "42px 18px 0" }}>
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
        <div
          style={{
            height: 38,
            borderRadius: 19,
            background: "#E0ECFF",
            border: "1px solid #C7DAFF",
            display: "flex",
            alignItems: "center",
            gap: 7,
            padding: "0 13px",
            color: C.blue,
            fontSize: 13,
            fontWeight: 800,
          }}
        >
          <GraduationCap size={18} />
          KIET
        </div>
        <div style={{ display: "flex", gap: 9 }}>
          <TopCircle icon={Sparkles} light />
          <TopCircle icon={Bell} light />
        </div>
      </div>
      <div style={{ marginTop: 18, display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 7 }}>
        <LightTab label="For You" active />
        <LightTab label="Moderation" />
        <LightTab label="Syllabus" />
      </div>
      <div
        style={{
          marginTop: 16,
          height: 48,
          borderRadius: 16,
          background: "#FFFFFF",
          border: "1px solid #E2E8F0",
          display: "flex",
          alignItems: "center",
          gap: 10,
          padding: "0 13px",
          color: "#64748B",
          fontSize: 13,
          fontWeight: 650,
        }}
      >
        <Search size={18} />
        Search resources...
        <Filter size={18} style={{ marginLeft: "auto" }} />
      </div>
      <ResourceLightCard title="Data Structures notes" type="NOTES" icon={FileText} />
      <ResourceLightCard title="Maths PYQ set" type="PYQ" icon={Folder} />
      <ResourceLightCard title="YouTube lecture guide" type="VIDEO" icon={Video} />
    </div>
    <BottomNav active="home" light />
  </AbsoluteFill>
);

const TopCircle: React.FC<{ icon: LucideIcon; light?: boolean }> = ({ icon: Icon, light }) => (
  <div
    style={{
      width: 38,
      height: 38,
      borderRadius: 19,
      background: light ? "#FFFFFF" : "#171B24",
      border: `1px solid ${light ? "#E2E8F0" : C.border}`,
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
    }}
  >
    <Icon size={18} color={light ? "#0F172A" : C.text} />
  </div>
);

const LightTab: React.FC<{ label: string; active?: boolean }> = ({ label, active }) => (
  <div
    style={{
      height: 38,
      borderRadius: 14,
      background: active ? C.blue : "#FFFFFF",
      border: `1px solid ${active ? C.blue : "#E2E8F0"}`,
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      color: active ? "#fff" : "#475569",
      fontSize: 12,
      fontWeight: 800,
    }}
  >
    {label}
  </div>
);

const ResourceLightCard: React.FC<{ title: string; type: string; icon: LucideIcon }> = ({
  title,
  type,
  icon: Icon,
}) => (
  <div
    style={{
      marginTop: 14,
      borderRadius: 22,
      background: "#FFFFFF",
      border: "1px solid #E2E8F0",
      padding: 15,
      boxShadow: "0 12px 26px rgba(15,23,42,0.06)",
    }}
  >
    <div style={{ display: "flex", alignItems: "center", gap: 11 }}>
      <IconBubble icon={Icon} color={C.blueLight} size={42} fill="#EFF6FF" />
      <div style={{ flex: 1 }}>
        <div style={{ color: "#0F172A", fontSize: 16, fontWeight: 800 }}>{title}</div>
        <div style={{ marginTop: 4, color: "#64748B", fontSize: 11, fontWeight: 800 }}>{type}</div>
      </div>
      <Download size={19} color={C.blueLight} />
    </div>
  </div>
);

const FloatingClockOverlay: React.FC<{ start: number; forceLight?: boolean }> = ({
  start,
  forceLight,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const local = frame - sf(start, fps);
  const appear = spring({
    frame: local,
    fps,
    config: { damping: 180 },
    durationInFrames: 24,
  });
  const rotate = local * 3.4;
  const progressValue = interpolate(Math.sin(local / 36), [-1, 1], [0.58, 0.82]);
  const darkBg = "#1E293BCC";
  const lightBg = "rgba(255,255,255,0.92)";
  const bg = forceLight ? lightBg : darkBg;
  const text = forceLight ? "#0F172A" : "#F8FAFC";
  const ring = forceLight ? "#4F46E5" : "#818CF8";

  return (
    <div
      style={{
        position: "absolute",
        right: 18,
        top: 116,
        width: 72,
        height: 72,
        borderRadius: 36,
        background: bg,
        border: `1.5px solid ${forceLight ? "rgba(255,255,255,0.6)" : "rgba(255,255,255,0.15)"}`,
        boxShadow: forceLight ? "0 8px 16px rgba(15,23,42,0.15)" : "0 8px 16px rgba(0,0,0,0.3)",
        opacity: appear,
        transform: `scale(${interpolate(appear, [0, 1], [0.55, 1], clamp)}) rotate(${interpolate(appear, [0, 1], [-18, 0], clamp)}deg)`,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
      }}
    >
      <div
        style={{
          position: "absolute",
          width: 66,
          height: 66,
          borderRadius: 33,
          background: `conic-gradient(${ring} ${progressValue * 360}deg, rgba(148,163,184,0.18) 0deg)`,
          transform: `rotate(${rotate}deg)`,
        }}
      />
      <div style={{ position: "absolute", width: 58, height: 58, borderRadius: 29, background: bg }} />
      <div
        style={{
          position: "relative",
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          gap: 1,
          color: text,
          fontFamily: "Roboto Mono, monospace",
          fontSize: 12,
          fontWeight: 800,
        }}
      >
        <Clock size={12} color={ring} />
        24:32
      </div>
    </div>
  );
};

const DownloadScreen: React.FC<{ start: number }> = ({ start }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const local = frame - sf(start, fps);
  const glow = interpolate(Math.sin(local / 16), [-1, 1], [0.18, 0.38]);
  const steps = ["Open studyshare.in", "Tap Download Android APK", "Install and choose your college"];

  return (
    <AbsoluteFill style={{ background: "#000", ...baseText }}>
      <StatusBar />
      <div style={{ padding: "104px 34px 0", textAlign: "center" }}>
        <Img
          src={staticFile("assets/app_icon.png")}
          style={{
            width: 138,
            height: 138,
            borderRadius: 34,
            objectFit: "cover",
            boxShadow: `0 0 58px rgba(37,99,235,${glow})`,
          }}
        />
        <div style={{ marginTop: 26, fontSize: 31, lineHeight: 1.05, fontWeight: 800 }}>Download StudyShare</div>
        <div style={{ marginTop: 12, color: C.sub, fontSize: 16, lineHeight: 1.35, fontWeight: 650 }}>
          Currently available as an Android APK.
        </div>
        <div
          style={{
            marginTop: 30,
            borderRadius: 25,
            background: C.blue,
            height: 62,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            gap: 11,
            color: "#fff",
            fontSize: 19,
            fontWeight: 800,
          }}
        >
          <Download size={24} />
          studyshare.in
        </div>
        <div
          style={{
            marginTop: 20,
            borderRadius: 22,
            background: "#121722",
            border: `1px solid ${C.border}`,
            padding: 17,
            textAlign: "left",
          }}
        >
          {steps.map((step, index) => {
            const stepIn = spring({
              frame: local - sf(1.8 + index * 0.45, fps),
              fps,
              config: { damping: 200 },
              durationInFrames: 18,
            });
            return (
              <div
                key={step}
                style={{
                  display: "flex",
                  gap: 12,
                  alignItems: "center",
                  marginTop: index === 0 ? 0 : 14,
                  opacity: stepIn,
                  transform: `translateX(${px(interpolate(stepIn, [0, 1], [-18, 0], clamp))})`,
                }}
              >
                <div
                  style={{
                    width: 28,
                    height: 28,
                    borderRadius: 14,
                    background: "rgba(37,99,235,0.22)",
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    color: C.blueLight,
                    fontSize: 14,
                    fontWeight: 800,
                  }}
                >
                  {index + 1}
                </div>
                <div style={{ color: C.sub, fontSize: 15, fontWeight: 750 }}>{step}</div>
              </div>
            );
          })}
        </div>
      </div>
    </AbsoluteFill>
  );
};

const Finale: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const opacity = interpolate(frame, [sf(91.8, fps), sf(93.3, fps)], [0, 1], clamp);
  const local = frame - sf(91.8, fps);
  const logoScale = spring({
    frame: local - sf(0.8, fps),
    fps,
    config: { damping: 160 },
    durationInFrames: 28,
  });
  const ringRotation = local * 3.2;

  return (
    <AbsoluteFill
      style={{
        opacity,
        alignItems: "center",
        justifyContent: "center",
        ...baseText,
      }}
    >
      <div style={{ position: "relative", width: 390, height: 390, display: "flex", alignItems: "center", justifyContent: "center" }}>
        {[0, 1, 2].map((index) => (
          <div
            key={index}
            style={{
              position: "absolute",
              width: 220 + index * 70,
              height: 220 + index * 70,
              borderRadius: "50%",
              border: `2px solid rgba(59,130,246,${0.42 - index * 0.1})`,
              borderTopColor: index === 1 ? C.orange : C.blueLight,
              borderRightColor: "rgba(255,255,255,0.08)",
              transform: `rotate(${ringRotation * (index % 2 === 0 ? 1 : -1)}deg)`,
            }}
          />
        ))}
        <Img
          src={staticFile("assets/app_icon.png")}
          style={{
            width: 180,
            height: 180,
            borderRadius: 46,
            objectFit: "cover",
            transform: `scale(${logoScale}) rotate(${interpolate(logoScale, [0, 1], [-18, 0], clamp)}deg)`,
            boxShadow: "0 28px 80px rgba(37,99,235,0.38)",
          }}
        />
      </div>
      <div style={{ fontSize: 76, fontWeight: 800, marginTop: 4 }}>StudyShare</div>
      <div style={{ fontSize: 30, color: C.sub, fontWeight: 750, marginTop: 12 }}>
        Your college study space.
      </div>
      <div style={{ fontSize: 29, color: C.blueLight, fontWeight: 800, marginTop: 32 }}>
        studyshare.in
      </div>
    </AbsoluteFill>
  );
};

const SceneTicks: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const active = copyScenes.findIndex((scene) => frame >= sf(scene.start, fps) && frame < sf(scene.end, fps));
  const opacity = interpolate(frame, [0, sf(0.9, fps), sf(91.7, fps), sf(93, fps)], [0, 1, 1, 0], clamp);

  return (
    <div
      style={{
        position: "absolute",
        left: 92,
        right: 92,
        bottom: 46,
        display: "flex",
        gap: 10,
        opacity,
      }}
    >
      {copyScenes.map((scene, index) => (
        <div
          key={scene.kicker}
          style={{
            flex: 1,
            height: 5,
            borderRadius: 6,
            background: index <= active ? (scene.accent ?? C.blueLight) : "rgba(255,255,255,0.18)",
          }}
        />
      ))}
    </div>
  );
};

export const StudyShareHorizontal: React.FC = () => {
  return (
    <AbsoluteFill style={{ background: C.bg, overflow: "hidden" }}>
      <Audio src={staticFile("audio/studyshare-launch-voiceover.mp3")} volume={1} />
      <LaunchBackground />
      {copyScenes.map((scene) => (
        <CopyBlock key={scene.kicker} scene={scene} />
      ))}
      <PhoneStage />
      <SceneTicks />
      <Finale />
    </AbsoluteFill>
  );
};
