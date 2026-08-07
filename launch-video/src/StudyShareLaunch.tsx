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
  Bookmark,
  Bot,
  Building2,
  CalendarCheck,
  CheckCircle2,
  ChevronDown,
  Clock,
  ClipboardCheck,
  CreditCard,
  Crown,
  Download,
  FileText,
  Folder,
  GraduationCap,
  Home,
  MessageSquare,
  Plus,
  Search,
  Send,
  Settings,
  Sparkles,
  Trophy,
  Users,
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
  blueDark: "#1D4ED8",
  accent: "#8B5CF6",
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

const baseText: CSSProperties = {
  fontFamily,
  color: C.text,
  letterSpacing: 0,
};

const IconBubble: React.FC<{
  icon: LucideIcon;
  color?: string;
  size?: number;
  fill?: string;
}> = ({ icon: Icon, color = C.blueLight, size = 52, fill }) => (
  <div
    style={{
      width: size,
      height: size,
      borderRadius: 16,
      background: fill ?? `${color}24`,
      border: `1px solid ${color}44`,
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      flex: "none",
    }}
  >
    <Icon size={Math.round(size * 0.47)} color={color} strokeWidth={2.6} />
  </div>
);

const Background: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const drift = progress(frame, fps, 0, 72, Easing.linear);
  const pulse = interpolate(Math.sin(frame / 38), [-1, 1], [0.25, 0.55]);

  return (
    <AbsoluteFill
      style={{
        background: `linear-gradient(180deg, #020409 0%, #050814 44%, #000 100%)`,
        overflow: "hidden",
      }}
    >
      <div
        style={{
          position: "absolute",
          inset: -180,
          opacity: 0.2,
          backgroundImage:
            "linear-gradient(rgba(59,130,246,0.26) 1px, transparent 1px), linear-gradient(90deg, rgba(59,130,246,0.2) 1px, transparent 1px)",
          backgroundSize: "88px 88px",
          transform: `translateY(${px(-140 * drift)}) rotate(-8deg)`,
        }}
      />
      <div
        style={{
          position: "absolute",
          top: -220,
          left: -120,
          width: 1320,
          height: 640,
          opacity: 0.46,
          background:
            "linear-gradient(100deg, transparent 0%, rgba(37,99,235,0.22) 35%, rgba(139,92,246,0.16) 52%, transparent 74%)",
          transform: `translateX(${px(-160 + drift * 300)}) rotate(-10deg)`,
          filter: "blur(28px)",
        }}
      />
      <div
        style={{
          position: "absolute",
          right: -240,
          bottom: 130,
          width: 820,
          height: 540,
          opacity: pulse,
          background:
            "linear-gradient(110deg, transparent 0%, rgba(37,99,235,0.22) 40%, rgba(249,115,22,0.13) 66%, transparent 100%)",
          transform: `rotate(18deg) translateY(${px(Math.sin(frame / 55) * 42)})`,
          filter: "blur(34px)",
        }}
      />
      <div
        style={{
          position: "absolute",
          inset: 0,
          background:
            "radial-gradient(circle at 50% 0%, rgba(37,99,235,0.2), transparent 42%), linear-gradient(180deg, rgba(0,0,0,0) 0%, rgba(0,0,0,0.66) 100%)",
        }}
      />
    </AbsoluteFill>
  );
};

type CopyScene = {
  start: number;
  end: number;
  kicker: string;
  title: string;
  body: string;
  chips: string[];
  align: "left" | "right" | "center";
};

const copyScenes: CopyScene[] = [
  {
    start: 0,
    end: 7,
    kicker: "Launch walkthrough",
    title: "Your college study space, finally in one app.",
    body: "Notes, PYQs, videos, syllabus, notices, chat rooms and AI tools are brought into one focused student workflow.",
    chips: ["Hook", "One app", "Android APK"],
    align: "center",
  },
  {
    start: 7,
    end: 18,
    kicker: "College pages",
    title: "Built around your college.",
    body: "Different college pages are part of StudyShare. KIET launches first as the fully functional page; other college materials are coming soon.",
    chips: ["KIET live", "More colleges soon", "College-first"],
    align: "left",
  },
  {
    start: 18,
    end: 31,
    kicker: "Resource discovery",
    title: "Find the right material before class starts.",
    body: "Sorted by college, semester, branch and subject. Search, filters, bookmarks, votes and downloads stay within reach.",
    chips: ["Notes", "PYQs", "Videos", "Syllabus"],
    align: "left",
  },
  {
    start: 31,
    end: 43,
    kicker: "Campus layer",
    title: "Follow departments. Get notice alerts.",
    body: "When followed departments post new notices, StudyShare can notify you. Rooms keep class conversations, saved posts and communities organized.",
    chips: ["Department follows", "Notice notifications", "Rooms"],
    align: "right",
  },
  {
    start: 43,
    end: 54,
    kicker: "Attendance",
    title: "Track attendance before it becomes a problem.",
    body: "For KIET, sync ERP once to see overall and subject-wise percentages, low attendance risk, day-wise records, upcoming classes and calendar reminders.",
    chips: ["KIET ERP", "Low attendance risk", "Calendar reminders"],
    align: "left",
  },
  {
    start: 54,
    end: 68,
    kicker: "AI Studio",
    title: "Turn any PDF or YouTube video into study mode.",
    body: "OCR summaries, practice quizzes, flashcards and Study Chat work from the exact resource you open.",
    chips: ["Summary", "Quiz", "Cards", "Chat"],
    align: "center",
  },
  {
    start: 68,
    end: 83,
    kicker: "Premium",
    title: "Track growth. Upgrade when you need more.",
    body: "Profile stats, badge stickers and monthly AI credits stay visible. Premium adds offline downloads, one year room validity, a badge and 10x AI credits.",
    chips: ["Rs 49/month", "Rs 149/quarter", "10x AI credits"],
    align: "right",
  },
  {
    start: 83,
    end: 92,
    kicker: "Download",
    title: "Visit studyshare.in and download the Android APK.",
    body: "StudyShare is currently available on Android.",
    chips: ["studyshare.in", "Android APK"],
    align: "center",
  },
];

const CopyBlock: React.FC<{ scene: CopyScene }> = ({ scene }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const opacity = fadeBetween(frame, fps, scene.start, scene.end, 0.35);
  const local = frame - sf(scene.start, fps);
  const enter = spring({
    frame: local,
    fps,
    config: { damping: 200 },
    durationInFrames: 22,
  });
  const y = interpolate(enter, [0, 1], [34, 0], clamp);
  const scale = interpolate(enter, [0, 1], [0.96, 1], clamp);
  const isCenter = scene.align === "center";
  const width = scene.align === "center" ? 870 : 455;
  const left =
    scene.align === "left" ? 68 : scene.align === "right" ? 552 : (1080 - width) / 2;
  const top = scene.start < 7.5 ? 118 : isCenter ? 112 : 196;

  return (
    <div
      style={{
        position: "absolute",
        top,
        left,
        width,
        opacity,
        transform: `translateY(${px(y)}) scale(${scale})`,
        textAlign: isCenter ? "center" : "left",
        ...baseText,
      }}
    >
      <div
        style={{
          display: "inline-flex",
          gap: 10,
          alignItems: "center",
          padding: "8px 14px",
          borderRadius: 999,
          background: "rgba(37,99,235,0.14)",
          border: "1px solid rgba(59,130,246,0.42)",
          color: C.blueLight,
          fontWeight: 800,
          fontSize: 24,
          lineHeight: 1,
        }}
      >
        <Sparkles size={22} />
        {scene.kicker}
      </div>
      <div
        style={{
          marginTop: 22,
          fontSize: scene.start < 7.5 ? 76 : 58,
          lineHeight: 1.03,
          fontWeight: 800,
          color: C.text,
        }}
      >
        {scene.title}
      </div>
      <div
        style={{
          marginTop: 18,
          color: C.sub,
          fontSize: 29,
          lineHeight: 1.35,
          fontWeight: 500,
        }}
      >
        {scene.body}
      </div>
      <div
        style={{
          marginTop: 24,
          display: "flex",
          flexWrap: "wrap",
          gap: 12,
          justifyContent: isCenter ? "center" : "flex-start",
        }}
      >
        {scene.chips.map((chip, index) => {
          const chipIn = spring({
            frame: local - 10 - index * 3,
            fps,
            config: { damping: 200 },
            durationInFrames: 18,
          });
          return (
            <div
              key={chip}
              style={{
                opacity: chipIn,
                transform: `translateY(${px(interpolate(chipIn, [0, 1], [16, 0]))})`,
                padding: "10px 14px",
                borderRadius: 999,
                background: "rgba(255,255,255,0.07)",
                border: "1px solid rgba(255,255,255,0.12)",
                color: C.text,
                fontSize: 22,
                fontWeight: 700,
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
  const intro = progress(frame, fps, 0, 1.1, Easing.out(Easing.cubic));
  const outroFade = interpolate(frame, [sf(92, fps), sf(93.4, fps)], [1, 0], clamp);
  const motionFrames = [
    sf(0, fps),
    sf(1.2, fps),
    sf(6.8, fps),
    sf(7.4, fps),
    sf(18, fps),
    sf(30.2, fps),
    sf(31.2, fps),
    sf(42.1, fps),
    sf(43.1, fps),
    sf(53.4, fps),
    sf(54.3, fps),
    sf(67.2, fps),
    sf(68.2, fps),
    sf(82.1, fps),
    sf(83.1, fps),
    sf(92, fps),
  ];
  const x = interpolate(
    frame,
    motionFrames,
    [0, 0, 236, 236, 236, 236, -285, -285, 300, 300, -135, -135, -300, -300, 0, 0],
    clamp,
  );
  const y = interpolate(
    frame,
    motionFrames,
    [80, 80, 178, 178, 178, 178, 196, 196, 178, 178, 196, 196, 198, 198, 172, 172],
    clamp,
  );
  const scale = interpolate(
    frame,
    motionFrames,
    [0.72, 0.72, 0.78, 0.78, 0.78, 0.78, 0.77, 0.77, 0.79, 0.79, 0.94, 0.96, 0.78, 0.78, 0.8, 0.8],
    clamp,
  );

  return (
    <div
      style={{
        position: "absolute",
        left: 304,
        top: 488,
        width: 472,
        height: 982,
        opacity: intro * outroFade,
        transform: `translate(${px(x)}, ${px(y)}) scale(${scale})`,
        transformOrigin: "center top",
        filter: "drop-shadow(0 44px 70px rgba(0,0,0,0.68))",
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
        width: 472,
        height: 982,
        borderRadius: 74,
        background: "#050505",
        padding: 18,
        boxShadow:
          "inset 0 0 0 2px rgba(255,255,255,0.16), inset 0 0 0 8px rgba(255,255,255,0.04)",
        position: "relative",
      }}
    >
      <div
        style={{
          width: "100%",
          height: "100%",
          borderRadius: 58,
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
          top: 30,
          left: "50%",
          width: 132,
          height: 38,
          marginLeft: -66,
          borderRadius: 999,
          background: "#050505",
          border: "1px solid rgba(255,255,255,0.08)",
        }}
      />
    </div>
  );
};

const PhoneContent: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const screens = [
    { start: 0, end: 18.8, component: <CollegePageScreen start={0} /> },
    { start: 17, end: 31.8, component: <ResourceFeedScreen start={17} /> },
    { start: 30.2, end: 43.8, component: <CampusScreen start={30.2} /> },
    { start: 42, end: 54.8, component: <AttendancePhoneScreen start={42} /> },
    { start: 52.4, end: 69, component: <AiStudioScreen start={52.4} /> },
    { start: 66.8, end: 84.2, component: <ProfilePremiumScreen start={66.8} /> },
    { start: 82.5, end: 93, component: <DownloadScreen start={82.5} /> },
  ];

  return (
    <AbsoluteFill style={{ background: "#000" }}>
      {screens.map((screen) => (
        <AbsoluteFill
          key={`${screen.start}-${screen.end}`}
          style={{
            opacity: fadeBetween(frame, fps, screen.start, screen.end, 0.48),
          }}
        >
          {screen.component}
        </AbsoluteFill>
      ))}
    </AbsoluteFill>
  );
};

const StatusBar: React.FC = () => (
  <div
    style={{
      height: 56,
      padding: "17px 22px 0",
      display: "flex",
      alignItems: "flex-start",
      justifyContent: "space-between",
      color: "#fff",
      fontFamily,
      fontSize: 18,
      fontWeight: 700,
    }}
  >
    <div>10:30</div>
    <div style={{ display: "flex", gap: 7, alignItems: "center" }}>
      <div style={{ display: "flex", gap: 3, height: 18, alignItems: "flex-end" }}>
        {[7, 10, 14, 18].map((h, i) => (
          <div
            key={h}
            style={{
              width: 4,
              height: h,
              borderRadius: 3,
              background: i === 0 ? "#A1A1AA" : "#fff",
            }}
          />
        ))}
      </div>
      <div
        style={{
          width: 25,
          height: 17,
          borderRadius: 5,
          border: "2px solid #fff",
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
            background: "#fff",
          }}
        />
      </div>
    </div>
  </div>
);

const BottomNav: React.FC<{ active: "home" | "chats" | "notices" | "profile" }> = ({
  active,
}) => {
  const items: Array<{ id: typeof active; label: string; icon: LucideIcon }> = [
    { id: "home", label: "Home", icon: Home },
    { id: "chats", label: "Chats", icon: MessageSquare },
    { id: "notices", label: "Notices", icon: Bell },
    { id: "profile", label: "Profile", icon: Users },
  ];

  return (
    <div
      style={{
        position: "absolute",
        left: 18,
        right: 18,
        bottom: 18,
        height: 78,
        borderRadius: 39,
        background: "rgba(23,23,23,0.94)",
        border: "1px solid rgba(255,255,255,0.12)",
        display: "flex",
        alignItems: "center",
        justifyContent: "space-around",
        boxShadow: "0 -16px 40px rgba(0,0,0,0.38)",
      }}
    >
      {items.map(({ id, label, icon: Icon }, index) => {
        const isActive = active === id;
        return (
          <div
            key={id}
            style={{
              width: index === 1 ? 76 : 82,
              display: "flex",
              flexDirection: "column",
              alignItems: "center",
              gap: 5,
              color: isActive ? C.blueLight : "#A7AAB3",
              fontFamily,
              fontSize: 14,
              fontWeight: 700,
            }}
          >
            <Icon size={24} strokeWidth={2.5} />
            {label}
          </div>
        );
      })}
      <div
        style={{
          position: "absolute",
          top: -32,
          left: "50%",
          marginLeft: -38,
          width: 76,
          height: 76,
          borderRadius: 38,
          background: C.blue,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          boxShadow: "0 16px 36px rgba(37,99,235,0.35)",
        }}
      >
        <Plus size={34} color="#fff" strokeWidth={2.5} />
      </div>
    </div>
  );
};

const CollegePageScreen: React.FC<{ start: number }> = ({ start }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const local = frame - sf(start, fps);
  const pageSlide = progress(local, fps, 6.3, 8.8);

  return (
    <AbsoluteFill style={{ background: "#000", ...baseText }}>
      <StatusBar />
      <div style={{ padding: "58px 24px 0" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 14 }}>
          <Img
            src={staticFile("assets/app_icon.png")}
            style={{ width: 58, height: 58, borderRadius: 18, objectFit: "cover" }}
          />
          <div>
            <div style={{ fontSize: 28, fontWeight: 800 }}>StudyShare</div>
            <div style={{ color: C.sub, marginTop: 4, fontSize: 16, fontWeight: 650 }}>
              College-first study pages
            </div>
          </div>
        </div>
        <div style={{ marginTop: 36, fontSize: 34, lineHeight: 1.08, fontWeight: 800 }}>
          Choose your college page
        </div>
        <div style={{ marginTop: 10, color: C.sub, fontSize: 18, lineHeight: 1.35, fontWeight: 600 }}>
          KIET is the first page launching with the complete StudyShare workflow.
        </div>
        <div style={{ marginTop: 28, transform: `translateX(${px(-pageSlide * 18)})`, display: "flex", gap: 16, width: 690 }}>
          <CollegeCard
            title="KIET Group of Institutions"
            status="Fully functional"
            active
            features={["Resources", "Notices", "Rooms", "Attendance", "AI Studio"]}
          />
          <CollegeCard
            title="More colleges"
            status="Materials coming soon"
            features={["Notes library", "College pages", "Campus updates"]}
          />
        </div>
        <div
          style={{
            marginTop: 28,
            borderRadius: 24,
            background: "rgba(37,99,235,0.14)",
            border: "1px solid rgba(59,130,246,0.36)",
            padding: 18,
            display: "flex",
            alignItems: "center",
            gap: 14,
          }}
        >
          <IconBubble icon={Building2} color={C.blueLight} size={50} />
          <div>
            <div style={{ fontSize: 19, fontWeight: 800 }}>KIET page is live first</div>
            <div style={{ marginTop: 5, color: C.sub, fontSize: 15, lineHeight: 1.3, fontWeight: 600 }}>
              Other college material libraries will be added soon.
            </div>
          </div>
        </div>
      </div>
      <BottomNav active="home" />
    </AbsoluteFill>
  );
};

const CollegeCard: React.FC<{
  title: string;
  status: string;
  active?: boolean;
  features: string[];
}> = ({ title, status, active, features }) => (
  <div
    style={{
      width: 310,
      minHeight: 292,
      borderRadius: 28,
      background: active
        ? "linear-gradient(160deg, rgba(37,99,235,0.36), rgba(23,27,36,0.98))"
        : "#171B24",
      border: `1px solid ${active ? "rgba(59,130,246,0.58)" : C.border}`,
      padding: 22,
      flex: "none",
    }}
  >
    <IconBubble icon={active ? GraduationCap : Building2} color={active ? C.blueLight : C.muted} size={58} />
    <div style={{ marginTop: 18, fontSize: 24, lineHeight: 1.12, fontWeight: 800 }}>{title}</div>
    <div style={{ marginTop: 8, color: active ? "#BFDBFE" : C.sub, fontSize: 16, fontWeight: 800 }}>
      {status}
    </div>
    <div style={{ marginTop: 16, display: "flex", flexWrap: "wrap", gap: 8 }}>
      {features.map((feature) => (
        <Pill key={feature} label={feature} active={active && feature === "Attendance"} />
      ))}
    </div>
  </div>
);

const ResourceFeedScreen: React.FC<{ start: number }> = ({ start }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const local = frame - sf(start, fps);
  const scroll = interpolate(local, [sf(8.2, fps), sf(13.5, fps)], [0, -118], clamp);
  const tap = spring({ frame: local - sf(10.8, fps), fps, config: { damping: 14, stiffness: 180 } });
  const tapScale = interpolate(tap, [0, 0.5, 1], [0, 1.35, 0], clamp);

  return (
    <AbsoluteFill style={{ background: "#000", ...baseText }}>
      <StatusBar />
      <div style={{ padding: "42px 22px 0" }}>
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
          <div
            style={{
              height: 44,
              borderRadius: 22,
              border: `1px solid ${C.blueDark}`,
              color: C.blueLight,
              padding: "0 16px",
              display: "flex",
              alignItems: "center",
              gap: 8,
              fontSize: 17,
              fontWeight: 800,
              background: "rgba(37,99,235,0.1)",
            }}
          >
            <GraduationCap size={20} />
            KIET
            <ChevronDown size={16} />
          </div>
          <Sparkles size={28} color={C.sub} />
          <Bookmark size={26} color={C.sub} />
          <ClipboardCheck size={27} color={C.sub} />
          <Bell size={27} color={C.sub} />
        </div>
        <Segmented tabs={["For You", "Following", "Syllabus"]} active={0} style={{ marginTop: 62 }} />
        <div
          style={{
            height: 68,
            borderRadius: 36,
            border: `1px solid ${C.border}`,
            marginTop: 18,
            display: "flex",
            alignItems: "center",
            padding: "0 20px",
            gap: 15,
            color: C.sub,
            fontSize: 23,
            fontWeight: 700,
            background: "rgba(255,255,255,0.02)",
            position: "relative",
          }}
        >
          <Search size={28} />
          Search resources...
          <Settings size={26} style={{ marginLeft: "auto" }} />
          <div
            style={{
              position: "absolute",
              right: 18,
              top: 13,
              width: 42,
              height: 42,
              borderRadius: 21,
              border: `2px solid rgba(59,130,246,${tapScale * 0.9})`,
              transform: `scale(${tapScale})`,
              opacity: tapScale > 0 ? 1 : 0,
            }}
          />
        </div>
        <div
          style={{
            marginTop: 18,
            display: "flex",
            justifyContent: "space-between",
            alignItems: "center",
            color: C.sub,
            fontSize: 16,
            fontWeight: 800,
          }}
        >
          <span>Resources scope</span>
          <div style={{ display: "flex", gap: 8 }}>
            <Pill label="Relevant" active />
            <Pill label="All" />
          </div>
        </div>
        <div style={{ marginTop: 14, transform: `translateY(${px(scroll)})` }}>
          <ResourceCard title="Data Structures notes" tag="NOTES" subject="CSE/CS" votes="+12" icon={FileText} />
          <ResourceCard title="CSE PYQ 2024" tag="PYQ" subject="Algorithms" votes="+8" icon={ClipboardCheck} accent={C.orange} />
          <ResourceCard title="Electrochemistry PDF" tag="NOTES" subject="Chemistry" votes="+7" icon={FileText} />
          <ResourceCard title="Network Layers video" tag="VIDEO" subject="Computer Networks" votes="+5" icon={Zap} accent={C.accent} />
        </div>
      </div>
      <BottomNav active="home" />
    </AbsoluteFill>
  );
};

const Segmented: React.FC<{ tabs: string[]; active: number; style?: CSSProperties }> = ({
  tabs,
  active,
  style,
}) => (
  <div
    style={{
      height: 74,
      borderRadius: 38,
      background: "#20232B",
      border: "1px solid rgba(255,255,255,0.12)",
      display: "grid",
      gridTemplateColumns: `repeat(${tabs.length}, 1fr)`,
      padding: 6,
      gap: 6,
      ...style,
    }}
  >
    {tabs.map((tab, index) => (
      <div
        key={tab}
        style={{
          borderRadius: 32,
          background: index === active ? C.blue : "transparent",
          color: index === active ? "#fff" : "#A7AAB3",
          fontWeight: 800,
          fontSize: 20,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
        }}
      >
        {tab}
      </div>
    ))}
  </div>
);

const Pill: React.FC<{ label: string; active?: boolean }> = ({ label, active }) => (
  <div
    style={{
      borderRadius: 18,
      background: active ? "rgba(37,99,235,0.28)" : "#191D25",
      border: `1px solid ${active ? "rgba(59,130,246,0.42)" : "rgba(255,255,255,0.1)"}`,
      color: active ? C.blueLight : C.sub,
      padding: "6px 12px",
      fontSize: 13,
      fontWeight: 800,
    }}
  >
    {label}
  </div>
);

const ResourceCard: React.FC<{
  title: string;
  tag: string;
  subject: string;
  votes: string;
  icon: LucideIcon;
  accent?: string;
}> = ({ title, tag, subject, votes, icon: Icon, accent = C.blueLight }) => (
  <div
    style={{
      height: 128,
      borderRadius: 22,
      background: "#171B24",
      border: "1px solid rgba(255,255,255,0.1)",
      marginBottom: 14,
      padding: 18,
      display: "flex",
      gap: 16,
      alignItems: "center",
    }}
  >
    <IconBubble icon={Icon} color={accent} size={58} />
    <div style={{ flex: 1, minWidth: 0 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
        <div style={{ fontSize: 22, fontWeight: 800, color: "#fff", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{title}</div>
        <Pill label={tag} active />
      </div>
      <div style={{ color: "#AAB0BC", marginTop: 8, fontSize: 16, fontWeight: 600 }}>
        {subject}
      </div>
      <div style={{ display: "flex", gap: 20, marginTop: 12, color: "#AAB0BC", fontSize: 16, alignItems: "center" }}>
        <span style={{ color: C.green, fontWeight: 800 }}>{votes}</span>
        <Bookmark size={19} />
        <Download size={19} />
        <span>1w ago</span>
      </div>
    </div>
  </div>
);

const AiStudioScreen: React.FC<{ start: number }> = ({ start }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const local = frame - sf(start, fps);
  const tab = local < sf(8, fps) ? 0 : local < sf(12.8, fps) ? 1 : local < sf(15.8, fps) ? 2 : 3;
  const progressValue = interpolate(local, [sf(4, fps), sf(10, fps)], [0.05, 0.92], clamp);

  return (
    <AbsoluteFill style={{ background: "#05070D", ...baseText }}>
      <StatusBar />
      <div style={{ height: 74, padding: "4px 24px", display: "flex", gap: 18, alignItems: "center", color: C.sub }}>
        <FileText size={30} />
        <div style={{ fontSize: 24, fontWeight: 800, flex: 1 }}>Study Material...</div>
        <Search size={28} />
        <Sparkles size={29} />
        <Download size={28} />
      </div>
      <div
        style={{
          position: "absolute",
          inset: "142px 0 0",
          padding: "18px 18px 0",
          background: "linear-gradient(180deg, #0B1220 0%, #05070D 100%)",
          borderTopLeftRadius: 44,
          borderTopRightRadius: 44,
          borderTop: `1px solid ${C.border}`,
        }}
      >
        <div
          style={{
            borderRadius: 24,
            background: "#101827",
            border: "1px solid rgba(59,130,246,0.18)",
            padding: 16,
            display: "flex",
            alignItems: "center",
            gap: 12,
          }}
        >
          <IconBubble icon={Bot} color={C.blueLight} size={48} />
          <div style={{ flex: 1 }}>
            <div style={{ fontSize: 21, fontWeight: 800 }}>AI Studio</div>
            <div style={{ fontSize: 15, color: C.sub, marginTop: 3 }}>Electrochemistry Detailed.pdf</div>
          </div>
          <Pill label="0/3" />
        </div>
        <div
          style={{
            height: 52,
            borderRadius: 18,
            border: `1px solid ${C.border}`,
            marginTop: 12,
            display: "flex",
            alignItems: "center",
            padding: "0 18px",
            gap: 12,
            fontSize: 19,
            fontWeight: 800,
          }}
        >
          <Settings size={23} />
          OCR on
        </div>
        <div
          style={{
            height: 74,
            borderRadius: 22,
            border: "1px solid rgba(59,130,246,0.22)",
            marginTop: 12,
            background: "#0F1828",
            display: "grid",
            gridTemplateColumns: "repeat(4, 1fr)",
            padding: 6,
            gap: 5,
          }}
        >
          {[
            ["Summary", FileText],
            ["Quiz", ClipboardCheck],
            ["Cards", Bookmark],
            ["Chat", MessageSquare],
          ].map(([label, Icon], index) => (
            <div
              key={label as string}
              style={{
                borderRadius: 16,
                background: index === tab ? "rgba(255,255,255,0.13)" : "transparent",
                border: index === tab ? "1px solid rgba(255,255,255,0.12)" : "1px solid transparent",
                display: "flex",
                flexDirection: "column",
                alignItems: "center",
                justifyContent: "center",
                gap: 3,
                color: index === tab ? "#fff" : C.sub,
                fontSize: 13,
                fontWeight: 800,
              }}
            >
              {React.createElement(Icon as LucideIcon, { size: 18 })}
              {label as string}
            </div>
          ))}
        </div>
        <div style={{ position: "relative", height: 510, marginTop: 12, overflow: "hidden" }}>
          <AiStageSummary local={local} progressValue={progressValue} />
          <AiStageQuiz local={local} />
          <AiStageCards local={local} />
          <AiStageChat local={local} />
        </div>
        <div
          style={{
            position: "absolute",
            left: 18,
            right: 18,
            bottom: 20,
            height: 60,
            borderRadius: 24,
            background: "rgba(255,255,255,0.12)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            gap: 10,
            color: "#fff",
            fontSize: 18,
            fontWeight: 800,
          }}
        >
          <Sparkles size={22} />
          Generate Summary
        </div>
      </div>
    </AbsoluteFill>
  );
};

const stageOpacity = (local: number, fps: number, start: number, end: number) =>
  Math.min(
    interpolate(local, [sf(start, fps), sf(start + 0.5, fps)], [0, 1], clamp),
    interpolate(local, [sf(end - 0.5, fps), sf(end, fps)], [1, 0], clamp),
  );

const AiStageSummary: React.FC<{ local: number; progressValue: number }> = ({ local, progressValue }) => {
  const { fps } = useVideoConfig();
  const opacity = stageOpacity(local, fps, 0, 10.7);
  const generateOpacity = interpolate(local, [sf(0, fps), sf(3, fps), sf(4, fps)], [1, 1, 0], clamp);
  const progressOpacity = interpolate(local, [sf(3.2, fps), sf(4, fps), sf(10, fps)], [0, 1, 1], clamp);
  const summaryOpacity = interpolate(local, [sf(8.9, fps), sf(10.5, fps)], [0, 1], clamp);
  const tapScale = spring({ frame: local - sf(2.2, fps), fps, config: { damping: 15, stiffness: 180 } });

  return (
    <div style={{ position: "absolute", inset: 0, opacity }}>
      <div
        style={{
          position: "absolute",
          inset: 0,
          borderRadius: 22,
          background: "#0D1422",
          border: `1px solid ${C.border}`,
          overflow: "hidden",
        }}
      >
        <div style={{ padding: 18, opacity: generateOpacity }}>
          <div style={{ height: 22, width: "70%", background: "#202633", borderRadius: 9, marginBottom: 12 }} />
          {[0, 1, 2, 3, 4].map((i) => (
            <div
              key={i}
              style={{
                height: 12,
                width: `${88 - i * 8}%`,
                background: "rgba(255,255,255,0.08)",
                borderRadius: 8,
                marginBottom: 12,
              }}
            />
          ))}
          <div
            style={{
              marginTop: 34,
              height: 68,
              borderRadius: 24,
              background: `linear-gradient(135deg, ${C.blue}, ${C.orange})`,
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              gap: 10,
              fontSize: 21,
              fontWeight: 800,
            }}
          >
            <Sparkles size={24} />
            Generate Summary
          </div>
          <div
            style={{
              position: "absolute",
              left: 190,
              top: 218,
              width: 60,
              height: 60,
              borderRadius: 30,
              border: `3px solid rgba(255,255,255,${Math.max(0, tapScale - 0.4)})`,
              transform: `scale(${interpolate(tapScale, [0, 1], [0.4, 1.25], clamp)})`,
            }}
          />
        </div>
        <div style={{ position: "absolute", inset: 0, padding: 18, opacity: progressOpacity }}>
          <div
            style={{
              height: 58,
              borderRadius: 20,
              border: `1px solid ${C.border}`,
              display: "flex",
              alignItems: "center",
              gap: 12,
              padding: "0 18px",
              fontSize: 20,
              fontWeight: 800,
            }}
          >
            <div
              style={{
                width: 24,
                height: 24,
                borderRadius: 14,
                border: `5px solid ${C.blue}`,
                borderTopColor: "transparent",
                transform: `rotate(${local * 12}deg)`,
              }}
            />
            Generating summary...
          </div>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 12, marginTop: 18 }}>
            <MiniMetric label="Score" value="60" />
            <MiniMetric label="High score" value="60" />
            <MiniMetric label="Level" value="1" />
          </div>
          <div
            style={{
              marginTop: 18,
              height: 266,
              borderRadius: 26,
              background: "linear-gradient(180deg, #09142E, #172554)",
              border: `1px solid ${C.border}`,
              padding: 18,
              overflow: "hidden",
            }}
          >
            <div style={{ fontSize: 20, fontWeight: 800 }}>Brick Blitz</div>
            <div style={{ marginTop: 38, display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 10 }}>
              {["#0EA5E9", "#F59E0B", "#22C55E", "#F97316", "#8B5CF6", "#2563EB", "#EAB308", "#14B8A6"].map((color, i) => (
                <div key={i} style={{ height: 26, borderRadius: 14, background: color, opacity: 0.9 }} />
              ))}
            </div>
            <div
              style={{
                position: "absolute",
                left: 132 + progressValue * 110,
                top: 255,
                width: 90,
                height: 14,
                borderRadius: 9,
                background: "#9CA3AF",
              }}
            />
          </div>
        </div>
        <div style={{ position: "absolute", inset: 0, padding: 20, opacity: summaryOpacity }}>
          <div style={{ fontSize: 22, fontWeight: 800, marginBottom: 14 }}>AI summary ready</div>
          {[
            "Electrode potential forms when ions move between a metal and solution.",
            "Osmosis depends on solute concentration and pressure difference.",
            "Key exam terms are highlighted for quick revision.",
          ].map((line, i) => (
            <div key={line} style={{ display: "flex", gap: 11, marginBottom: 14, color: C.sub, fontSize: 17, lineHeight: 1.28, fontWeight: 600 }}>
              <CheckCircle2 size={21} color={C.green} />
              <span>{line}</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};

const AiStageQuiz: React.FC<{ local: number }> = ({ local }) => {
  const { fps } = useVideoConfig();
  const opacity = stageOpacity(local, fps, 10.2, 13.6);
  return (
    <div style={{ position: "absolute", inset: 0, opacity }}>
      <div style={{ borderRadius: 22, background: "#0D1422", border: `1px solid ${C.border}`, padding: 20, height: "100%" }}>
        <div style={{ fontSize: 22, fontWeight: 800 }}>Practice quiz</div>
        <div style={{ color: C.sub, marginTop: 6, fontSize: 16, fontWeight: 600 }}>Question 1 of 10</div>
        <div style={{ marginTop: 22, fontSize: 20, lineHeight: 1.25, fontWeight: 800 }}>
          Which term describes potential difference at an electrode?
        </div>
        {["Electrode potential", "Osmotic pressure", "Capacitance", "Diffusion current"].map((answer, i) => (
          <div
            key={answer}
            style={{
              marginTop: 13,
              padding: "13px 15px",
              borderRadius: 16,
              background: i === 0 ? "rgba(5,150,105,0.16)" : "#171F2F",
              border: `1px solid ${i === 0 ? "rgba(5,150,105,0.5)" : C.border}`,
              fontSize: 16,
              fontWeight: 700,
              display: "flex",
              justifyContent: "space-between",
              color: i === 0 ? "#A7F3D0" : C.sub,
            }}
          >
            {answer}
            {i === 0 ? <CheckCircle2 size={20} color={C.green} /> : null}
          </div>
        ))}
      </div>
    </div>
  );
};

const AiStageCards: React.FC<{ local: number }> = ({ local }) => {
  const { fps } = useVideoConfig();
  const opacity = stageOpacity(local, fps, 13, 16.5);
  const flip = progress(local, fps, 13.4, 15.4);
  const rotate = interpolate(flip, [0, 1], [0, 180], clamp);
  return (
    <div style={{ position: "absolute", inset: 0, opacity, perspective: 900 }}>
      <div
        style={{
          height: 350,
          marginTop: 52,
          borderRadius: 28,
          background: `linear-gradient(135deg, ${C.blue}, ${C.accent})`,
          border: "1px solid rgba(255,255,255,0.18)",
          padding: 26,
          transform: `rotateY(${rotate}deg)`,
          display: "flex",
          flexDirection: "column",
          justifyContent: "space-between",
          boxShadow: "0 30px 60px rgba(37,99,235,0.26)",
        }}
      >
        <Pill label={flip > 0.52 ? "Answer" : "Question"} />
        <div style={{ fontSize: 27, lineHeight: 1.15, fontWeight: 800 }}>
          {flip > 0.52 ? "Potential difference between metal and solution." : "What is electrode potential?"}
        </div>
        <div style={{ fontSize: 16, color: "rgba(255,255,255,0.84)", fontWeight: 700 }}>Tap to flip | Swipe next</div>
      </div>
    </div>
  );
};

const AiStageChat: React.FC<{ local: number }> = ({ local }) => {
  const { fps } = useVideoConfig();
  const opacity = interpolate(local, [sf(15.7, fps), sf(16.6, fps)], [0, 1], clamp);
  return (
    <div style={{ position: "absolute", inset: 0, opacity }}>
      <div style={{ borderRadius: 22, background: "#0D1422", border: `1px solid ${C.border}`, padding: 18, height: "100%" }}>
        <div style={{ fontSize: 22, fontWeight: 800 }}>Study Chat</div>
        <ChatBubble side="left" text="Ask anything from this PDF. I can cite the exact page." />
        <ChatBubble side="right" text="Explain electrode potential in simple words." />
        <ChatBubble side="left" text="It is the voltage created when a metal meets its ion solution. Page 1 has the definition and example." />
      </div>
    </div>
  );
};

const MiniMetric: React.FC<{ label: string; value: string }> = ({ label, value }) => (
  <div style={{ borderRadius: 18, background: "#252D3D", border: `1px solid ${C.border}`, padding: 12 }}>
    <div style={{ color: C.sub, fontSize: 13, fontWeight: 800 }}>{label}</div>
    <div style={{ color: "#fff", fontSize: 24, fontWeight: 800, marginTop: 8 }}>{value}</div>
  </div>
);

const ChatBubble: React.FC<{ side: "left" | "right"; text: string }> = ({ side, text }) => (
  <div
    style={{
      maxWidth: side === "right" ? "78%" : "84%",
      marginLeft: side === "right" ? "auto" : 0,
      marginTop: 14,
      padding: "12px 14px",
      borderRadius: side === "right" ? "18px 18px 6px 18px" : "18px 18px 18px 6px",
      background: side === "right" ? C.blue : "#202839",
      color: "#fff",
      fontSize: 15,
      lineHeight: 1.3,
      fontWeight: 650,
    }}
  >
    {text}
  </div>
);

const CampusScreen: React.FC<{ start: number }> = ({ start }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const local = frame - sf(start, fps);
  const showRooms = progress(local, fps, 7.2, 8.8);
  const notificationIn = spring({
    frame: local - sf(3.1, fps),
    fps,
    config: { damping: 200 },
    durationInFrames: 22,
  });
  return (
    <AbsoluteFill style={{ background: "#000", ...baseText }}>
      <StatusBar />
      <div style={{ padding: "54px 22px 0" }}>
        <div style={{ fontSize: 30, fontWeight: 800, display: "flex", alignItems: "center", gap: 12 }}>
          <Bell size={31} color={C.blueLight} />
          Department notices
        </div>
        <div style={{ color: C.sub, marginTop: 6, fontSize: 17, fontWeight: 600 }}>
          Follow departments and get notified when they post.
        </div>
        <div
          style={{
            marginTop: 18,
            borderRadius: 24,
            background: "rgba(37,99,235,0.15)",
            border: "1px solid rgba(59,130,246,0.38)",
            padding: 15,
            display: "flex",
            alignItems: "center",
            gap: 12,
          }}
        >
          <IconBubble icon={BellRing} color={C.blueLight} size={48} />
          <div style={{ flex: 1 }}>
            <div style={{ fontSize: 19, fontWeight: 800 }}>Following CSE</div>
            <div style={{ color: C.sub, marginTop: 4, fontSize: 14, fontWeight: 650 }}>
              New notices trigger notifications.
            </div>
          </div>
          <Pill label="Notify me" active />
        </div>
        <div
          style={{
            position: "absolute",
            top: 184,
            left: 44,
            right: 44,
            borderRadius: 22,
            background: "rgba(23,27,36,0.96)",
            border: "1px solid rgba(255,255,255,0.14)",
            padding: "14px 16px",
            display: "flex",
            alignItems: "center",
            gap: 12,
            transform: `translateY(${px(interpolate(notificationIn, [0, 1], [-28, 0], clamp))}) scale(${interpolate(notificationIn, [0, 1], [0.96, 1], clamp)})`,
            opacity: notificationIn,
            zIndex: 3,
            boxShadow: "0 18px 34px rgba(0,0,0,0.36)",
          }}
        >
          <IconBubble icon={BellRing} color={C.orange} size={42} />
          <div>
            <div style={{ fontSize: 17, fontWeight: 800 }}>New CSE notice</div>
            <div style={{ color: C.sub, fontSize: 13, marginTop: 3, fontWeight: 650 }}>
              Workshop on AI tools posted just now.
            </div>
          </div>
        </div>
        <div
          style={{
            marginTop: 18,
            transform: `translateX(${px(-showRooms * 440)})`,
            display: "flex",
            width: 860,
            gap: 22,
          }}
        >
          <div style={{ width: 420, flex: "none" }}>
            <NoticeCard title="Exam form deadline" dept="General" detail="Complete registration before Friday" />
            <NoticeCard title="Workshop on AI tools" dept="CSE" detail="Auditorium, 3 PM today" />
            <NoticeCard title="Question bank updated" dept="ECE" detail="New PYQs added for semester 1" />
          </div>
          <div style={{ width: 420, flex: "none" }}>
            <RoomCard title="CSE Sem 1 Doubts" members="286 members" />
            <RoomCard title="Data Structures PYQ prep" members="143 members" />
            <RoomCard title="Discover college rooms" members="Join with room code" accent={C.accent} />
          </div>
        </div>
      </div>
      <BottomNav active={showRooms > 0.5 ? "chats" : "notices"} />
    </AbsoluteFill>
  );
};

const NoticeCard: React.FC<{ title: string; dept: string; detail: string }> = ({ title, dept, detail }) => (
  <div style={{ borderRadius: 24, background: "#171B24", border: `1px solid ${C.border}`, padding: 18, marginBottom: 16 }}>
    <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
      <IconBubble icon={Bell} color={C.orange} size={50} />
      <div style={{ flex: 1 }}>
        <div style={{ fontSize: 21, fontWeight: 800 }}>{title}</div>
        <div style={{ color: C.sub, marginTop: 5, fontSize: 15, fontWeight: 650 }}>{dept} notice</div>
      </div>
    </div>
    <div style={{ marginTop: 15, color: C.sub, fontSize: 16, lineHeight: 1.25, fontWeight: 600 }}>{detail}</div>
  </div>
);

const RoomCard: React.FC<{ title: string; members: string; accent?: string }> = ({ title, members, accent = C.blueLight }) => (
  <div style={{ borderRadius: 24, background: "#171B24", border: `1px solid ${C.border}`, padding: 18, marginBottom: 16 }}>
    <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
      <IconBubble icon={MessageSquare} color={accent} size={50} />
      <div style={{ flex: 1 }}>
        <div style={{ fontSize: 21, fontWeight: 800 }}>{title}</div>
        <div style={{ color: C.sub, marginTop: 5, fontSize: 15, fontWeight: 650 }}>{members}</div>
      </div>
    </div>
    <div style={{ marginTop: 14, display: "flex", gap: 8 }}>
      <Pill label="Saved posts" />
      <Pill label="Discover" active />
    </div>
  </div>
);

const AttendancePhoneScreen: React.FC<{ start: number }> = ({ start }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const local = frame - sf(start, fps);
  const ring = progress(local, fps, 1.4, 4.4);
  const riskIn = spring({
    frame: local - sf(4.8, fps),
    fps,
    config: { damping: 200 },
    durationInFrames: 24,
  });
  const scheduleIn = spring({
    frame: local - sf(6.6, fps),
    fps,
    config: { damping: 200 },
    durationInFrames: 24,
  });

  return (
    <AbsoluteFill style={{ background: "#000", ...baseText }}>
      <StatusBar />
      <div style={{ padding: "54px 22px 0" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
          <CalendarCheck size={32} color={C.blueLight} />
          <div>
            <div style={{ fontSize: 30, fontWeight: 800 }}>Attendance</div>
            <div style={{ marginTop: 4, color: C.sub, fontSize: 16, fontWeight: 650 }}>
              KIET ERP synced
            </div>
          </div>
        </div>
        <div
          style={{
            marginTop: 26,
            borderRadius: 28,
            background: "#101827",
            border: "1px solid rgba(59,130,246,0.26)",
            padding: 22,
            display: "flex",
            alignItems: "center",
            gap: 20,
          }}
        >
          <div style={{ width: 142, height: 142, position: "relative", display: "flex", alignItems: "center", justifyContent: "center" }}>
            <div
              style={{
                position: "absolute",
                inset: 0,
                borderRadius: "50%",
                background: `conic-gradient(${C.blueLight} ${ring * 282}deg, #242B38 0deg)`,
              }}
            />
            <div style={{ position: "absolute", inset: 12, borderRadius: "50%", background: "#101827" }} />
            <div style={{ position: "relative", textAlign: "center" }}>
              <div style={{ fontSize: 34, fontWeight: 800 }}>78%</div>
              <div style={{ color: C.sub, fontSize: 12, fontWeight: 800 }}>Overall</div>
            </div>
          </div>
          <div style={{ flex: 1 }}>
            <div style={{ fontSize: 21, fontWeight: 800 }}>Overall attendance</div>
            <div style={{ marginTop: 8, color: C.sub, fontSize: 15, lineHeight: 1.35, fontWeight: 650 }}>
              Present classes, total classes and subject risk stay visible after sync.
            </div>
            <div style={{ marginTop: 13, display: "flex", gap: 8 }}>
              <Pill label="Synced" active />
              <Pill label="75% target" />
            </div>
          </div>
        </div>
        <div
          style={{
            marginTop: 18,
            transform: `translateY(${px(interpolate(riskIn, [0, 1], [28, 0], clamp))})`,
            opacity: riskIn,
          }}
        >
          <AttendanceSubject name="Engineering Chemistry" percent="71%" risky />
          <AttendanceSubject name="Data Structures" percent="84%" />
          <AttendanceSubject name="Mathematics" percent="80%" />
        </div>
        <div
          style={{
            marginTop: 18,
            borderRadius: 24,
            background: "rgba(5,150,105,0.11)",
            border: "1px solid rgba(5,150,105,0.34)",
            padding: 17,
            display: "flex",
            alignItems: "center",
            gap: 14,
            transform: `translateY(${px(interpolate(scheduleIn, [0, 1], [34, 0], clamp))})`,
            opacity: scheduleIn,
          }}
        >
          <IconBubble icon={Clock} color="#34D399" size={50} />
          <div>
            <div style={{ fontSize: 18, fontWeight: 800 }}>Upcoming classes</div>
            <div style={{ color: C.sub, marginTop: 4, fontSize: 14, fontWeight: 650 }}>
              Add schedule reminders to your calendar.
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
      height: 76,
      borderRadius: 20,
      background: "#171B24",
      border: `1px solid ${risky ? "rgba(249,115,22,0.5)" : C.border}`,
      marginBottom: 12,
      padding: "0 16px",
      display: "flex",
      alignItems: "center",
      gap: 12,
    }}
  >
    <IconBubble icon={risky ? AlertTriangle : BarChart3} color={risky ? C.orange : C.blueLight} size={46} />
    <div style={{ flex: 1 }}>
      <div style={{ fontSize: 17, fontWeight: 800 }}>{name}</div>
      <div style={{ marginTop: 4, color: risky ? "#FDBA74" : C.sub, fontSize: 13, fontWeight: 700 }}>
        {risky ? "Low attendance risk" : "On track"}
      </div>
    </div>
    <div style={{ fontSize: 23, fontWeight: 800, color: risky ? C.orange : "#fff" }}>{percent}</div>
  </div>
);

const ProfilePremiumScreen: React.FC<{ start: number }> = ({ start }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const local = frame - sf(start, fps);
  const sheet = progress(local, fps, 5.2, 6.5);
  return (
    <AbsoluteFill style={{ background: "#000", ...baseText }}>
      <StatusBar />
      <div style={{ padding: "44px 22px 0", textAlign: "center" }}>
        <div style={{ fontSize: 28, fontWeight: 800 }}>My Profile</div>
        <div style={{ margin: "28px auto 0", width: 122, height: 122, borderRadius: 68, border: `5px solid ${C.gold}`, background: "#172033", display: "flex", alignItems: "center", justifyContent: "center" }}>
          <Trophy size={56} color={C.gold} />
        </div>
        <div style={{ marginTop: 22, fontSize: 32, fontWeight: 800, display: "flex", alignItems: "center", justifyContent: "center", gap: 9 }}>
          StudyShare Legend <BadgeCheck size={28} color={C.gold} fill={C.gold} />
        </div>
        <div style={{ marginTop: 9, color: C.sub, fontSize: 18, fontWeight: 600 }}>CSE/CS | Sem 1</div>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", marginTop: 30 }}>
          <ProfileStat value="46" label="Contributions" />
          <ProfileStat value="2" label="Followers" />
          <ProfileStat value="2" label="Following" />
        </div>
        <div style={{ marginTop: 26, borderRadius: 24, background: "#171717", border: `1px solid ${C.border}`, padding: 18, textAlign: "left" }}>
          <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
            <IconBubble icon={CreditCard} size={52} color={C.blueLight} />
            <div>
              <div style={{ fontSize: 21, fontWeight: 800 }}>Monthly AI Credits</div>
              <div style={{ color: C.sub, marginTop: 5, fontSize: 15, fontWeight: 600 }}>59 credits left</div>
            </div>
          </div>
          <div style={{ height: 10, borderRadius: 8, background: "#272727", marginTop: 16, overflow: "hidden" }}>
            <div style={{ height: "100%", width: "65%", background: C.blue }} />
          </div>
        </div>
      </div>
      <div
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          bottom: 0,
          height: 574,
          borderTopLeftRadius: 38,
          borderTopRightRadius: 38,
          background: "#0F172A",
          borderTop: "1px solid rgba(255,255,255,0.12)",
          padding: "24px 22px",
          transform: `translateY(${px((1 - sheet) * 420)})`,
          opacity: 0.22 + sheet * 0.78,
        }}
      >
        <div style={{ fontSize: 26, fontWeight: 800, display: "flex", alignItems: "center", gap: 10 }}>
          <Crown size={28} color={C.gold} />
          StudyShare Premium
        </div>
        <div style={{ color: C.sub, marginTop: 8, fontSize: 16, fontWeight: 600 }}>
          Student friendly plans and AI top ups.
        </div>
        <div style={{ marginTop: 18, display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12 }}>
          <PlanCard title="Monthly" price="Rs 49" />
          <PlanCard title="Quarterly" price="Rs 149" badge="Best value" />
        </div>
        <PremiumBenefit icon={Download} text="Offline PDF downloads" />
        <PremiumBenefit icon={MessageSquare} text="One year chat room validity" />
        <PremiumBenefit icon={BadgeCheck} text="Premium profile badge" />
        <PremiumBenefit icon={Zap} text="10x monthly AI credits and Rs 10 top ups" />
      </div>
      <BottomNav active="profile" />
    </AbsoluteFill>
  );
};

const ProfileStat: React.FC<{ value: string; label: string }> = ({ value, label }) => (
  <div>
    <div style={{ fontSize: 27, fontWeight: 800 }}>{value}</div>
    <div style={{ color: C.sub, fontSize: 15, marginTop: 6, fontWeight: 600 }}>{label}</div>
  </div>
);

const PlanCard: React.FC<{ title: string; price: string; badge?: string }> = ({ title, price, badge }) => (
  <div style={{ borderRadius: 20, border: `1px solid ${badge ? C.orange : C.border}`, background: badge ? "rgba(249,115,22,0.12)" : "#151D2B", padding: 14 }}>
    <div style={{ color: C.sub, fontSize: 14, fontWeight: 800 }}>{title}</div>
    <div style={{ fontSize: 24, fontWeight: 800, marginTop: 6 }}>{price}</div>
    {badge ? <div style={{ marginTop: 8, color: C.orange, fontSize: 13, fontWeight: 800 }}>{badge}</div> : null}
  </div>
);

const PremiumBenefit: React.FC<{ icon: LucideIcon; text: string }> = ({ icon: Icon, text }) => (
  <div style={{ display: "flex", alignItems: "center", gap: 12, marginTop: 14, color: C.sub, fontSize: 16, fontWeight: 700 }}>
    <CheckCircle2 size={20} color={C.green} />
    <Icon size={20} color={C.blueLight} />
    {text}
  </div>
);

const DownloadScreen: React.FC<{ start: number }> = ({ start }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const local = frame - sf(start, fps);
  const glow = interpolate(Math.sin(local / 16), [-1, 1], [0.18, 0.36]);
  return (
    <AbsoluteFill style={{ background: "#000", ...baseText }}>
      <StatusBar />
      <div style={{ padding: "122px 36px 0", textAlign: "center" }}>
        <Img
          src={staticFile("assets/app_icon.png")}
          style={{
            width: 146,
            height: 146,
            borderRadius: 36,
            objectFit: "cover",
            boxShadow: `0 0 58px rgba(37,99,235,${glow})`,
          }}
        />
        <div style={{ marginTop: 30, fontSize: 34, lineHeight: 1.05, fontWeight: 800 }}>
          Download StudyShare
        </div>
        <div style={{ marginTop: 14, color: C.sub, fontSize: 18, lineHeight: 1.35, fontWeight: 600 }}>
          Currently available as an Android APK.
        </div>
        <div
          style={{
            marginTop: 34,
            borderRadius: 26,
            background: C.blue,
            height: 66,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            gap: 12,
            color: "#fff",
            fontSize: 20,
            fontWeight: 800,
          }}
        >
          <Download size={25} />
          studyshare.in
        </div>
        <div style={{ marginTop: 22, borderRadius: 22, background: "#121722", border: `1px solid ${C.border}`, padding: 18, textAlign: "left" }}>
          {["Open studyshare.in", "Tap Download Android APK", "Install and choose your college"].map((step, i) => (
            <div key={step} style={{ display: "flex", gap: 13, alignItems: "center", marginTop: i === 0 ? 0 : 14 }}>
              <div style={{ width: 28, height: 28, borderRadius: 14, background: "rgba(37,99,235,0.22)", display: "flex", alignItems: "center", justifyContent: "center", color: C.blueLight, fontSize: 15, fontWeight: 800 }}>{i + 1}</div>
              <div style={{ color: C.sub, fontSize: 17, fontWeight: 700 }}>{step}</div>
            </div>
          ))}
        </div>
      </div>
    </AbsoluteFill>
  );
};

const Finale: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const opacity = interpolate(frame, [sf(91.6, fps), sf(93, fps)], [0, 1], clamp);
  const local = frame - sf(91, fps);
  const ringRotation = local * 2.7;
  const logoScale = spring({
    frame: local - sf(1.2, fps),
    fps,
    config: { damping: 180 },
    durationInFrames: 30,
  });
  return (
    <AbsoluteFill
      style={{
        opacity,
        alignItems: "center",
        justifyContent: "center",
        ...baseText,
      }}
    >
      <div style={{ position: "relative", width: 430, height: 430, display: "flex", alignItems: "center", justifyContent: "center" }}>
        {[0, 1, 2].map((i) => (
          <div
            key={i}
            style={{
              position: "absolute",
              width: 250 + i * 70,
              height: 250 + i * 70,
              borderRadius: "50%",
              border: `2px solid rgba(59,130,246,${0.42 - i * 0.1})`,
              borderTopColor: i === 1 ? C.orange : C.blueLight,
              borderRightColor: "rgba(255,255,255,0.08)",
              transform: `rotate(${ringRotation * (i % 2 === 0 ? 1 : -1)}deg)`,
            }}
          />
        ))}
        <Img
          src={staticFile("assets/app_icon.png")}
          style={{
            width: 190,
            height: 190,
            borderRadius: 48,
            objectFit: "cover",
            transform: `scale(${logoScale}) rotate(${interpolate(logoScale, [0, 1], [-18, 0], clamp)}deg)`,
            boxShadow: "0 28px 80px rgba(37,99,235,0.38)",
          }}
        />
      </div>
      <div style={{ fontSize: 70, fontWeight: 800, marginTop: 12 }}>StudyShare</div>
      <div style={{ fontSize: 30, color: C.sub, fontWeight: 700, marginTop: 12 }}>
        Your college study space.
      </div>
      <div style={{ fontSize: 28, color: C.blueLight, fontWeight: 800, marginTop: 34 }}>
        studyshare.in
      </div>
    </AbsoluteFill>
  );
};

const SceneTicks: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const active = copyScenes.findIndex((s) => frame >= sf(s.start, fps) && frame < sf(s.end, fps));
  const opacity = interpolate(frame, [0, sf(1, fps), sf(91.5, fps), sf(92.8, fps)], [0, 1, 1, 0], clamp);
  return (
    <div
      style={{
        position: "absolute",
        left: 82,
        right: 82,
        bottom: 54,
        display: "flex",
        gap: 10,
        opacity,
      }}
    >
      {copyScenes.slice(0, -1).map((scene, index) => (
        <div
          key={scene.kicker}
          style={{
            flex: 1,
            height: 5,
            borderRadius: 6,
            background: index <= active ? C.blueLight : "rgba(255,255,255,0.18)",
          }}
        />
      ))}
    </div>
  );
};

export const StudyShareLaunch: React.FC = () => {
  return (
    <AbsoluteFill style={{ background: C.bg, overflow: "hidden" }}>
      <Audio src={staticFile("audio/studyshare-launch-voiceover.mp3")} volume={1} />
      <Background />
      {copyScenes.map((scene) => (
        <CopyBlock key={scene.kicker} scene={scene} />
      ))}
      <PhoneStage />
      <SceneTicks />
      <Finale />
    </AbsoluteFill>
  );
};
