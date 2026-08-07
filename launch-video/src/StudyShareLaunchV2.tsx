import React, {CSSProperties} from "react";
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
import {loadFont as loadJakarta} from "@remotion/google-fonts/PlusJakartaSans";
import {loadFont as loadPlayfair} from "@remotion/google-fonts/PlayfairDisplay";
import {
  Bell,
  Bookmark,
  Bot,
  CalendarCheck,
  Check,
  ChevronRight,
  Clock3,
  Download,
  FileText,
  GraduationCap,
  MessageCircle,
  Moon,
  Search,
  Sparkles,
  Star,
  Sun,
  Trophy,
  Zap,
} from "lucide-react";

const bodyFont = loadJakarta("normal", {
  weights: ["400", "500", "600", "700", "800"],
  subsets: ["latin"],
}).fontFamily;

const displayFont = loadPlayfair("normal", {
  weights: ["600", "700", "800"],
  subsets: ["latin"],
}).fontFamily;

const C = {
  ink: "#101828",
  muted: "#667085",
  soft: "#F5F7FB",
  paper: "#FBFCFF",
  line: "#DDE4F0",
  blue: "#2563EB",
  blue2: "#3B82F6",
  cyan: "#45D9CF",
  green: "#16A34A",
  gold: "#F59E0B",
  dark: "#05070D",
  darkCard: "#111827",
  darkText: "#F8FAFC",
};

const fpsSeconds = (seconds: number, fps: number) => Math.round(seconds * fps);

const clamp = {
  extrapolateLeft: "clamp" as const,
  extrapolateRight: "clamp" as const,
};

const p = (
  frame: number,
  fps: number,
  start: number,
  end: number,
  easing = Easing.inOut(Easing.cubic),
) =>
  interpolate(frame, [fpsSeconds(start, fps), fpsSeconds(end, fps)], [0, 1], {
    ...clamp,
    easing,
  });

const sceneOpacity = (frame: number, fps: number, start: number, end: number) => {
  const fade = 0.45;
  const fadeIn = p(frame, fps, start, start + fade);
  const fadeOut = interpolate(frame, [fpsSeconds(end - fade, fps), fpsSeconds(end, fps)], [1, 0], clamp);
  return Math.min(fadeIn, fadeOut);
};

const localFrame = (frame: number, fps: number, start: number) =>
  Math.max(0, frame - fpsSeconds(start, fps));

const textStyle: CSSProperties = {
  fontFamily: bodyFont,
  color: C.ink,
  letterSpacing: 0,
};

const screenBase = {
  w: 430,
  h: 956,
  pad: 18,
};

const typeText = (text: string, progress: number) =>
  text.slice(0, Math.floor(text.length * progress));

const bgPattern = (frame: number): CSSProperties => ({
  background:
    "radial-gradient(circle at 20% 18%, rgba(69,217,207,0.18), transparent 28%), radial-gradient(circle at 82% 22%, rgba(37,99,235,0.15), transparent 30%), linear-gradient(135deg, #FCFDFF 0%, #F3F7FF 55%, #EEF8F6 100%)",
  overflow: "hidden",
  transform: `translate3d(${Math.sin(frame / 90) * 8}px, ${Math.cos(frame / 100) * 5}px, 0) scale(1.02)`,
});

const Grain = () => (
  <AbsoluteFill
    style={{
      opacity: 0.22,
      backgroundImage:
        "linear-gradient(rgba(16,24,40,0.04) 1px, transparent 1px), linear-gradient(90deg, rgba(16,24,40,0.04) 1px, transparent 1px)",
      backgroundSize: "54px 54px",
    }}
  />
);

const PhoneFrame: React.FC<{
  children: React.ReactNode;
  x?: number;
  y?: number;
  scale?: number;
  rotate?: number;
  opacity?: number;
}> = ({children, x = 0, y = 0, scale = 1, rotate = 0, opacity = 1}) => (
  <div
    style={{
      position: "absolute",
      left: 1110 + x,
      top: 54 + y,
      width: screenBase.w,
      height: screenBase.h,
      transform: `scale(${scale}) rotate(${rotate}deg)`,
      transformOrigin: "center",
      opacity,
      filter: "drop-shadow(0 36px 60px rgba(29,41,57,0.28))",
    }}
  >
    <div
      style={{
        position: "absolute",
        inset: 0,
        borderRadius: 70,
        background: "linear-gradient(135deg, #0D1117, #2A2F37 48%, #090B10)",
        boxShadow: "inset 0 0 0 2px rgba(255,255,255,0.18), inset 0 0 0 8px rgba(0,0,0,0.7)",
      }}
    />
    <div
      style={{
        position: "absolute",
        left: 50,
        right: 50,
        top: 16,
        height: 36,
        borderRadius: 22,
        background: "#05070A",
        zIndex: 5,
        boxShadow: "0 0 0 1px rgba(255,255,255,0.08)",
      }}
    />
    <div
      style={{
        position: "absolute",
        left: screenBase.pad,
        top: screenBase.pad,
        width: screenBase.w - screenBase.pad * 2,
        height: screenBase.h - screenBase.pad * 2,
        borderRadius: 54,
        overflow: "hidden",
        background: "#000",
      }}
    >
      {children}
    </div>
  </div>
);

const ScreenImage: React.FC<{
  src: string;
  zoom?: number;
  tx?: number;
  ty?: number;
  darken?: number;
  objectPosition?: string;
}> = ({src, zoom = 1, tx = 0, ty = 0, darken = 0, objectPosition = "center"}) => (
  <div style={{position: "absolute", inset: 0, overflow: "hidden"}}>
    <Img
      src={staticFile(src)}
      style={{
        width: "100%",
        height: "100%",
        objectFit: "cover",
        objectPosition,
        transform: `translate(${tx}px, ${ty}px) scale(${zoom})`,
      }}
    />
    {darken > 0 ? (
      <div style={{position: "absolute", inset: 0, background: `rgba(0,0,0,${darken})`}} />
    ) : null}
  </div>
);

const KineticTitle: React.FC<{
  kicker: string;
  title: string;
  body: string;
  chips?: string[];
  sceneStart: number;
}> = ({kicker, title, body, chips = [], sceneStart}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const lf = localFrame(frame, fps, sceneStart);
  const titleProgress = interpolate(lf, [8, 54], [0, 1], clamp);
  const enter = spring({frame: lf, fps, config: {damping: 18, stiffness: 120}});
  return (
    <div
      style={{
        ...textStyle,
        position: "absolute",
        left: 116,
        top: 178,
        width: 760,
        transform: `translateY(${(1 - enter) * 26}px)`,
      }}
    >
      <div
        style={{
          display: "inline-flex",
          alignItems: "center",
          gap: 10,
          padding: "9px 14px",
          borderRadius: 999,
          color: C.blue,
          background: "rgba(37,99,235,0.09)",
          border: "1px solid rgba(37,99,235,0.16)",
          fontSize: 22,
          fontWeight: 800,
        }}
      >
        <Sparkles size={22} />
        {kicker}
      </div>
      <div
        style={{
          marginTop: 30,
          fontFamily: displayFont,
          fontSize: 88,
          lineHeight: 0.98,
          fontWeight: 800,
          color: C.ink,
        }}
      >
        {typeText(title, titleProgress)}
        <span style={{color: C.blue}}>{titleProgress < 1 ? "|" : ""}</span>
      </div>
      <div
        style={{
          marginTop: 30,
          color: C.muted,
          fontSize: 31,
          lineHeight: 1.32,
          maxWidth: 700,
        }}
      >
        {body}
      </div>
      <div style={{display: "flex", flexWrap: "wrap", gap: 12, marginTop: 34}}>
        {chips.map((chip, index) => {
          const chipIn = p(frame, fps, sceneStart + 0.75 + index * 0.18, sceneStart + 1.2 + index * 0.18);
          return (
            <div
              key={chip}
              style={{
                padding: "12px 16px",
                borderRadius: 999,
                background: index % 2 === 0 ? "rgba(69,217,207,0.14)" : "rgba(37,99,235,0.1)",
                color: index % 2 === 0 ? "#08746D" : C.blue,
                border: `1px solid ${index % 2 === 0 ? "rgba(69,217,207,0.28)" : "rgba(37,99,235,0.18)"}`,
                fontSize: 21,
                fontWeight: 800,
                opacity: chipIn,
                transform: `translateY(${(1 - chipIn) * 18}px)`,
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

const HookScene = ({start, end}: {start: number; end: number}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const opacity = sceneOpacity(frame, fps, start, end);
  const lf = localFrame(frame, fps, start);
  const problem = [
    ["WhatsApp links", 0.3],
    ["Drive folders", 0.75],
    ["Notices", 1.15],
    ["ERP attendance", 1.55],
  ];
  return (
    <AbsoluteFill style={{opacity}}>
      <div
        style={{
          ...textStyle,
          position: "absolute",
          left: 134,
          top: 152,
          width: 860,
        }}
      >
        <div style={{fontSize: 28, fontWeight: 800, color: C.blue}}>StudyShare launch</div>
        <div
          style={{
            marginTop: 28,
            fontFamily: displayFont,
            fontSize: 96,
            lineHeight: 0.98,
            fontWeight: 800,
          }}
        >
          College study is scattered.
        </div>
        <div style={{marginTop: 32, fontSize: 34, color: C.muted, lineHeight: 1.32, maxWidth: 720}}>
          Notes, notices, attendance, and exam prep finally come into one app.
        </div>
        <div style={{marginTop: 44, display: "flex", flexWrap: "wrap", gap: 16, width: 700}}>
          {problem.map(([label, delay], i) => {
            const enter = interpolate(lf / fps, [delay, delay + 0.45], [0, 1], clamp);
            return (
              <div
                key={label}
                style={{
                  padding: "16px 19px",
                  borderRadius: 22,
                  fontSize: 25,
                  fontWeight: 800,
                  color: i === 3 ? C.green : C.ink,
                  background: "rgba(255,255,255,0.72)",
                  border: "1px solid rgba(16,24,40,0.08)",
                  boxShadow: "0 14px 34px rgba(29,41,57,0.08)",
                  opacity: enter,
                  transform: `translateY(${(1 - enter) * 22}px) rotate(${(1 - enter) * -2}deg)`,
                }}
              >
                {label}
              </div>
            );
          })}
        </div>
      </div>
      <PhoneFrame scale={0.86} rotate={-2} x={-24} y={10}>
        <ScreenImage src="assets/screens/latest-loaded-2.png" zoom={1.06} tx={0} ty={-8} />
      </PhoneFrame>
    </AbsoluteFill>
  );
};

const HomeScene = ({start, end}: {start: number; end: number}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const opacity = sceneOpacity(frame, fps, start, end);
  const zoom = 1 + p(frame, fps, start + 1, end - 0.6) * 0.09;
  return (
    <AbsoluteFill style={{opacity}}>
      <KineticTitle
        kicker="First college page"
        title="K. I. E. T. is live first."
        body="Different college pages are built in. K. I. E. T. launches fully functional now, and other college materials are coming soon."
        chips={["College pages", "K-I-E-T", "More colleges soon"]}
        sceneStart={start}
      />
      <PhoneFrame scale={0.88} x={-30} y={8}>
        <ScreenImage src="assets/screens/studyshare-site-mobile-wait.png" zoom={zoom} ty={-30} />
      </PhoneFrame>
    </AbsoluteFill>
  );
};

const ResourcesScene = ({start, end}: {start: number; end: number}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const opacity = sceneOpacity(frame, fps, start, end);
  const t = p(frame, fps, start + 1, end - 0.5);
  return (
    <AbsoluteFill style={{opacity}}>
      <KineticTitle
        kicker="Walkthrough"
        title="Resources in seconds."
        body="Notes, P.Y.Qs, videos, syllabus, and downloads are organized by semester, branch, and subject."
        chips={["Search", "Filter", "Bookmark", "Upvote", "Download"]}
        sceneStart={start}
      />
      <PhoneFrame scale={0.91} x={-18} y={-8}>
        <ScreenImage src="assets/screens/latest-loaded-2.png" zoom={1.02 + t * 0.18} tx={0} ty={-t * 160} />
      </PhoneFrame>
      <FloatingCallout x={1290} y={710} label="Relevant resources" icon={<Search size={24} />} progress={p(frame, fps, start + 2, start + 2.7)} />
    </AbsoluteFill>
  );
};

const NoticesScene = ({start, end}: {start: number; end: number}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const opacity = sceneOpacity(frame, fps, start, end);
  return (
    <AbsoluteFill style={{opacity}}>
      <KineticTitle
        kicker="Departments"
        title="Follow notices that matter."
        body="Follow departments like Artificial Intelligence, Events and Activities, and others to receive notice notifications."
        chips={["AI department", "Events", "Notification alerts"]}
        sceneStart={start}
      />
      <PhoneFrame scale={0.91} x={-18} y={-8}>
        <ScreenImage src="assets/screens/latest-notices-loaded2.png" zoom={1.02} />
      </PhoneFrame>
      <FloatingCallout x={1304} y={214} label="Department notice" icon={<Bell size={24} />} progress={p(frame, fps, start + 2, start + 2.7)} />
    </AbsoluteFill>
  );
};

const AttendanceScene = ({start, end}: {start: number; end: number}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const opacity = sceneOpacity(frame, fps, start, end);
  const t = p(frame, fps, start + 1, end - 1);
  return (
    <AbsoluteFill style={{opacity}}>
      <KineticTitle
        kicker="Attendance"
        title="ERP synced. Risk visible."
        body="Track overall attendance, subject-wise attendance, low-risk status, day-wise records, upcoming classes, and reminders."
        chips={["90.46% projected", "Subject cards", "CyberVidya sync"]}
        sceneStart={start}
      />
      <PhoneFrame scale={0.91} x={-18} y={-8}>
        <ScreenImage src="assets/recordings/frames/flow-17.png" zoom={1.02 + t * 0.1} ty={-t * 120} />
        <div
          style={{
            position: "absolute",
            left: 20,
            top: 66,
            width: 306,
            height: 108,
            borderRadius: 16,
            background: "#FFFFFF",
          }}
        />
        <div
          style={{
            ...textStyle,
            position: "absolute",
            left: 36,
            top: 76,
            fontSize: 12,
            fontWeight: 800,
            color: "#475467",
          }}
        >
          Current standing
        </div>
        <div
          style={{
            ...textStyle,
            position: "absolute",
            left: 36,
            top: 98,
            fontSize: 24,
            fontWeight: 900,
            color: C.ink,
            textTransform: "uppercase",
          }}
        >
          harsh attri
        </div>
        <div
          style={{
            ...textStyle,
            position: "absolute",
            left: 36,
            top: 132,
            fontSize: 17,
            fontWeight: 700,
            color: "#475467",
          }}
        >
          CSE-AIML | Sem 2
        </div>
      </PhoneFrame>
    </AbsoluteFill>
  );
};

const AIChatScene = ({start, end}: {start: number; end: number}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const opacity = sceneOpacity(frame, fps, start, end);
  const lf = localFrame(frame, fps, start);
  const msg1 = p(frame, fps, start + 1.5, start + 2.2);
  const msg2 = p(frame, fps, start + 2.4, start + 3.4);
  const msg3 = p(frame, fps, start + 4.1, start + 5.0);
  const msg4 = p(frame, fps, start + 5.4, start + 6.5);
  return (
    <AbsoluteFill style={{opacity}}>
      <KineticTitle
        kicker="AI Chat"
        title="Answers from your material."
        body="Ask from your own college PDFs, notices, and notes. Answers stay scoped to study material."
        chips={["College material", "PDF context", "Practice prompts"]}
        sceneStart={start}
      />
      <PhoneFrame scale={0.91} x={-18} y={-8}>
        <ScreenImage src="assets/screens/latest-ai-entry.png" zoom={1} darken={0.06} />
        <div style={{position: "absolute", inset: 0, background: "rgba(0,0,0,0.64)"}} />
        <ChatSurface>
          <ChatBubble
            type="user"
            progress={msg1}
            text="Summarize Unit 2 from my latest PDF."
            top={116}
          />
          <ChatBubble
            type="ai"
            progress={msg2}
            text="Unit 2 focuses on DSSC working, silica purification, fuel cells, and pollution control. Revise diagrams first, then solve the PYQ set."
            top={184}
          />
          <ChatBubble
            type="user"
            progress={msg3}
            text="Make 5 quick MCQs for practice."
            top={342}
          />
          <ChatBubble
            type="ai"
            progress={msg4}
            text="Done. I will test definitions, mechanisms, applications, and one numerical-style concept from the same resource."
            top={410}
          />
          <div
            style={{
              position: "absolute",
              left: 18,
              right: 18,
              bottom: 28,
              height: 64,
              borderRadius: 32,
              background: "#171A22",
              border: "1px solid rgba(255,255,255,0.08)",
              display: "flex",
              alignItems: "center",
              paddingLeft: 24,
              color: "#AEB4C0",
              fontFamily: bodyFont,
              fontSize: 22,
            }}
          >
            Message StudyShare AI
          </div>
        </ChatSurface>
      </PhoneFrame>
      <div
        style={{
          position: "absolute",
          left: 1260,
          top: 778,
          color: "rgba(37,99,235,0.12)",
          fontFamily: displayFont,
          fontSize: 84,
          transform: `rotate(${Math.sin(lf / 40) * 4}deg)`,
        }}
      >
        AI
      </div>
    </AbsoluteFill>
  );
};

const AIStudioScene = ({start, end}: {start: number; end: number}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const opacity = sceneOpacity(frame, fps, start, end);
  const phase = p(frame, fps, start + 1, end - 1);
  const screen =
    phase < 0.34
      ? "assets/screens/ai-studio-summary.png"
      : phase < 0.67
        ? "assets/screens/ai-studio-generating.png"
        : "assets/screens/ai-studio-cards.png";
  return (
    <AbsoluteFill style={{opacity}}>
      <KineticTitle
        kicker="AI Studio"
        title="Study from the exact file."
        body="Open a PDF or YouTube video. Keep OCR on, generate summaries, practice quizzes, flashcards, and study chat."
        chips={["OCR on", "Summary", "Quiz", "Cards", "Chat"]}
        sceneStart={start}
      />
      <PhoneFrame scale={0.91} x={-18} y={-8}>
        <ScreenImage src={screen} zoom={1.04} />
      </PhoneFrame>
    </AbsoluteFill>
  );
};

const PremiumScene = ({start, end}: {start: number; end: number}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const opacity = sceneOpacity(frame, fps, start, end);
  return (
    <AbsoluteFill style={{opacity}}>
      <KineticTitle
        kicker="Profile and Premium"
        title="Credits, badges, and Pro."
        body="Premium adds offline PDF downloads, one-year room validity, a premium badge, 10x monthly AI credits, and top-ups from Rs. 10."
        chips={["Offline PDFs", "1-year rooms", "Premium badge", "10x AI credits"]}
        sceneStart={start}
      />
      <PhoneFrame scale={0.91} x={-18} y={-8}>
        <ScreenImage src="assets/screens/latest-profile-loaded2.png" zoom={1.04} ty={-8} />
        <div style={{position: "absolute", left: 42, top: 76, width: 354, height: 334, borderRadius: 28, background: "#000"}} />
        <div style={{position: "absolute", left: 151, top: 112, width: 138, height: 138, borderRadius: 78, background: "linear-gradient(135deg, #13213B, #07111F)", border: "5px solid #FACC15", boxShadow: "0 0 28px rgba(250,204,21,0.58)", display: "flex", alignItems: "center", justifyContent: "center"}}>
          <div style={{...textStyle, fontSize: 58, color: "#FACC15", fontWeight: 950}}>H</div>
        </div>
        <div style={{position: "absolute", left: 276, top: 230, padding: "6px 12px", borderRadius: 999, background: "#022C22", color: "#10B981", fontFamily: bodyFont, fontWeight: 900, fontSize: 14}}>Pro</div>
        <div style={{...textStyle, position: "absolute", left: 0, right: 0, top: 279, textAlign: "center", fontSize: 29, color: "#fff", fontWeight: 900}}>harsh attri</div>
        <div style={{...textStyle, position: "absolute", left: 0, right: 0, top: 316, textAlign: "center", fontSize: 17, color: "#A8AFBD", fontWeight: 700}}>@harsh_attri</div>
        <div style={{position: "absolute", left: 82, top: 358, width: 276, height: 1, background: "linear-gradient(90deg, transparent, rgba(37,99,235,0.6), transparent)"}} />
      </PhoneFrame>
    </AbsoluteFill>
  );
};

const ThemeScene = ({start, end}: {start: number; end: number}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const opacity = sceneOpacity(frame, fps, start, end);
  const themeMix = p(frame, fps, start + 2, start + 4.8);
  return (
    <AbsoluteFill style={{opacity}}>
      <KineticTitle
        kicker="Motion details"
        title="Dark first. Light when needed."
        body="The app includes light mode, a sun-moon theme transition, and a floating study clock."
        chips={["Light mode", "Sun-moon transition", "Floating clock"]}
        sceneStart={start}
      />
      <PhoneFrame scale={0.91} x={-18} y={-8}>
        <div style={{position: "absolute", inset: 0}}>
          <ScreenImage src="assets/screens/latest-settings-dark.png" />
        </div>
        <div style={{position: "absolute", inset: 0, opacity: themeMix}}>
          <ScreenImage src="assets/screens/latest-settings-light.png" />
        </div>
        <ThemeOrb mix={themeMix} />
        <StudyClock progress={p(frame, fps, start + 4.6, start + 6.4)} />
      </PhoneFrame>
    </AbsoluteFill>
  );
};

const DownloadScene = ({start, end}: {start: number; end: number}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const opacity = sceneOpacity(frame, fps, start, end);
  return (
    <AbsoluteFill style={{opacity}}>
      <KineticTitle
        kicker="Download"
        title="Get the Android APK."
        body="Visit studyshare.in, tap Download, and install the APK. StudyShare is currently available on Android."
        chips={["studyshare.in", "Download v1.0.25", "Android APK"]}
        sceneStart={start}
      />
      <PhoneFrame scale={0.91} x={-18} y={-8}>
        <ScreenImage src="assets/screens/studyshare-site-mobile-wait.png" zoom={1.03} ty={-4} objectPosition="top center" />
      </PhoneFrame>
      <StepCard x={1210} y={190} label="1" title="Visit studyshare.in" progress={p(frame, fps, start + 1.2, start + 1.8)} />
      <StepCard x={1210} y={318} label="2" title="Tap Download" progress={p(frame, fps, start + 2.1, start + 2.8)} />
      <StepCard x={1210} y={446} label="3" title="Install Android APK" progress={p(frame, fps, start + 3.0, start + 3.7)} />
    </AbsoluteFill>
  );
};

const OutroScene = ({start, end}: {start: number; end: number}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const opacity = sceneOpacity(frame, fps, start, end);
  const lf = localFrame(frame, fps, start);
  const rot = lf * 3.2;
  const logoIn = spring({frame: lf, fps, config: {damping: 16, stiffness: 100}});
  return (
    <AbsoluteFill style={{opacity}}>
      <div
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          top: 0,
          bottom: 0,
          background: "radial-gradient(circle at center, #F7FBFF 0%, #EAF2FF 52%, #DFFAF8 100%)",
        }}
      />
      <div
        style={{
          position: "absolute",
          left: "50%",
          top: "45%",
          width: 300,
          height: 300,
          marginLeft: -150,
          marginTop: -150,
          borderRadius: 180,
          border: "4px solid rgba(37,99,235,0.18)",
          transform: `rotate(${rot}deg) scale(${0.6 + logoIn * 0.4})`,
        }}
      >
        <div style={{position: "absolute", inset: 24, borderRadius: 150, border: "8px dashed rgba(37,99,235,0.36)"}} />
      </div>
      <div
        style={{
          position: "absolute",
          left: "50%",
          top: "45%",
          width: 156,
          height: 156,
          marginLeft: -78,
          marginTop: -78,
          transform: `scale(${0.8 + logoIn * 0.2}) rotate(${-rot * 0.35}deg)`,
          filter: "drop-shadow(0 30px 45px rgba(37,99,235,0.28))",
        }}
      >
        <LogoMark size={156} />
      </div>
      <div
        style={{
          ...textStyle,
          position: "absolute",
          left: 0,
          right: 0,
          top: 690,
          textAlign: "center",
          fontFamily: displayFont,
          fontSize: 70,
          fontWeight: 800,
        }}
      >
        StudyShare
      </div>
      <div
        style={{
          ...textStyle,
          position: "absolute",
          left: 0,
          right: 0,
          top: 780,
          textAlign: "center",
          fontSize: 31,
          color: C.muted,
          fontWeight: 700,
        }}
      >
        Your college study space in one app.
      </div>
    </AbsoluteFill>
  );
};

const FloatingCallout = ({
  x,
  y,
  label,
  icon,
  progress,
}: {
  x: number;
  y: number;
  label: string;
  icon: React.ReactNode;
  progress: number;
}) => (
  <div
    style={{
      ...textStyle,
      position: "absolute",
      left: x,
      top: y,
      display: "flex",
      alignItems: "center",
      gap: 12,
      padding: "14px 16px",
      borderRadius: 20,
      background: "rgba(255,255,255,0.82)",
      border: "1px solid rgba(16,24,40,0.09)",
      boxShadow: "0 18px 42px rgba(29,41,57,0.16)",
      color: C.blue,
      fontSize: 20,
      fontWeight: 900,
      opacity: progress,
      transform: `translateY(${(1 - progress) * 24}px) scale(${0.92 + progress * 0.08})`,
    }}
  >
    {icon}
    {label}
  </div>
);

const ChatSurface = ({children}: {children: React.ReactNode}) => (
  <div style={{position: "absolute", inset: 0, background: "#050505"}}>
    <div style={{position: "absolute", left: 24, top: 42, color: "#fff", fontFamily: bodyFont, fontSize: 24, fontWeight: 900}}>AI Chat</div>
    <div style={{position: "absolute", left: 24, top: 72, color: "#858B99", fontFamily: bodyFont, fontSize: 14, fontWeight: 800}}>Smart study assistant</div>
    <Bot style={{position: "absolute", right: 28, top: 48, color: "#fff"}} size={28} />
    {children}
  </div>
);

const ChatBubble = ({
  type,
  text,
  progress,
  top,
}: {
  type: "user" | "ai";
  text: string;
  progress: number;
  top: number;
}) => {
  const isUser = type === "user";
  return (
    <div
      style={{
        ...textStyle,
        position: "absolute",
        left: isUser ? 92 : 22,
        right: isUser ? 20 : 74,
        top,
        padding: "14px 16px",
        borderRadius: isUser ? "22px 22px 6px 22px" : "22px 22px 22px 6px",
        background: isUser ? C.blue : "#171A22",
        border: isUser ? "none" : "1px solid rgba(255,255,255,0.09)",
        color: "#fff",
        fontSize: 18,
        lineHeight: 1.28,
        fontWeight: 650,
        opacity: progress,
        transform: `translateY(${(1 - progress) * 18}px) scale(${0.97 + progress * 0.03})`,
      }}
    >
      {text}
    </div>
  );
};

const ThemeOrb = ({mix}: {mix: number}) => (
  <div
    style={{
      position: "absolute",
      right: 28,
      top: 390,
      width: 92,
      height: 92,
      borderRadius: 60,
      background: mix > 0.5 ? "#FDB022" : "#EEF4FF",
      boxShadow: mix > 0.5 ? "0 0 30px rgba(245,158,11,0.45)" : "inset -18px -8px 0 #475467",
      transform: `translateX(${(1 - mix) * -210}px) rotate(${mix * 160}deg)`,
    }}
  />
);

const StudyClock = ({progress}: {progress: number}) => (
  <div
    style={{
      position: "absolute",
      left: 42,
      top: 705,
      width: 78,
      height: 78,
      borderRadius: 50,
      background: "rgba(255,255,255,0.88)",
      border: "1px solid rgba(37,99,235,0.18)",
      boxShadow: "0 14px 34px rgba(29,41,57,0.18)",
      opacity: progress,
      transform: `translateY(${(1 - progress) * 40}px)`,
    }}
  >
    <div
      style={{
        position: "absolute",
        inset: 8,
        borderRadius: 40,
        border: "4px solid rgba(37,99,235,0.18)",
        borderTopColor: C.blue,
        transform: `rotate(${progress * 240}deg)`,
      }}
    />
    <Clock3 size={22} style={{position: "absolute", left: 28, top: 18, color: C.blue}} />
    <div style={{position: "absolute", left: 16, right: 16, bottom: 15, textAlign: "center", fontFamily: bodyFont, fontSize: 14, fontWeight: 900, color: C.ink}}>
      24:32
    </div>
  </div>
);

const StepCard = ({x, y, label, title, progress}: {x: number; y: number; label: string; title: string; progress: number}) => (
  <div
    style={{
      ...textStyle,
      position: "absolute",
      left: x,
      top: y,
      width: 360,
      height: 86,
      borderRadius: 24,
      background: "rgba(255,255,255,0.84)",
      border: "1px solid rgba(16,24,40,0.09)",
      boxShadow: "0 18px 42px rgba(29,41,57,0.14)",
      display: "flex",
      alignItems: "center",
      gap: 18,
      padding: "0 24px",
      opacity: progress,
      transform: `translateX(${(1 - progress) * 42}px)`,
    }}
  >
    <div style={{width: 42, height: 42, borderRadius: 24, background: C.blue, color: "#fff", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 22, fontWeight: 900}}>
      {label}
    </div>
    <div style={{fontSize: 23, fontWeight: 900}}>{title}</div>
    <ChevronRight size={24} style={{marginLeft: "auto", color: C.blue}} />
  </div>
);

const scenes = [
  {start: 0, end: 10, Comp: HookScene},
  {start: 10, end: 21, Comp: HomeScene},
  {start: 21, end: 33, Comp: ResourcesScene},
  {start: 33, end: 45, Comp: NoticesScene},
  {start: 45, end: 58, Comp: AttendanceScene},
  {start: 58, end: 72, Comp: AIChatScene},
  {start: 72, end: 86, Comp: AIStudioScene},
  {start: 86, end: 98, Comp: PremiumScene},
  {start: 98, end: 108, Comp: ThemeScene},
  {start: 108, end: 116, Comp: DownloadScene},
  {start: 116, end: 120, Comp: OutroScene},
];

export const StudyShareLaunchV2 = () => {
  const frame = useCurrentFrame();
  return (
    <AbsoluteFill style={{background: C.paper}}>
      <AbsoluteFill style={bgPattern(frame)} />
      <Grain />
      <div
        style={{
          position: "absolute",
          inset: 38,
          borderRadius: 40,
          border: "1px solid rgba(37,99,235,0.08)",
          pointerEvents: "none",
        }}
      />
      <Audio src={staticFile("audio/studyshare-launch-voiceover.mp3")} />
      {scenes.map(({start, end, Comp}) => (
        <Comp key={start} start={start} end={end} />
      ))}
      <CornerBrand />
    </AbsoluteFill>
  );
};

const CornerBrand = () => (
  <div style={{position: "absolute", right: 70, bottom: 46, display: "flex", alignItems: "center", gap: 12, opacity: 0.72}}>
    <LogoMark size={34} />
    <div style={{fontFamily: bodyFont, fontSize: 20, fontWeight: 900, color: C.ink}}>StudyShare</div>
  </div>
);

const LogoMark = ({size}: {size: number}) => (
  <div
    style={{
      width: size,
      height: size,
      borderRadius: size / 2,
      background: "linear-gradient(135deg, #1D4ED8 0%, #2563EB 52%, #0F4DD6 100%)",
      position: "relative",
      overflow: "hidden",
    }}
  >
    {Array.from({length: 12}).map((_, index) => {
      const angle = (index / 12) * Math.PI * 2;
      const r = size * 0.27;
      const x = size / 2 + Math.cos(angle) * r;
      const y = size / 2 + Math.sin(angle) * r;
      return (
        <div
          key={index}
          style={{
            position: "absolute",
            left: x - size * 0.035,
            top: y - size * 0.012,
            width: size * 0.16,
            height: size * 0.034,
            borderRadius: size * 0.02,
            background: "rgba(255,255,255,0.9)",
            transform: `rotate(${(angle * 180) / Math.PI}deg)`,
            transformOrigin: `${size * 0.035}px center`,
          }}
        />
      );
    })}
    <div
      style={{
        position: "absolute",
        left: size * 0.31,
        top: size * 0.31,
        width: size * 0.38,
        height: size * 0.38,
        borderRadius: size * 0.2,
        border: `${Math.max(2, size * 0.025)}px solid rgba(255,255,255,0.22)`,
      }}
    />
  </div>
);
