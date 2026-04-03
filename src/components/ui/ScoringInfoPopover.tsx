import InfoPopover from './InfoPopover';

interface Props {
  i18n: {
    title: string;
    certSenior: string;
    certSeniorSub: string;
    certCpmai: string;
    certMid: string;
    certMidSub: string;
    certPractitioner: string;
    certPractitionerSub: string;
    certEntry: string;
    certEntrySub: string;
    specialization: string;
    specializationSub: string;
    trail: string;
    trailSub: string;
    knowledgeAiPm: string;
    knowledgeAiPmSub: string;
    course: string;
    badge: string;
    showcase: string;
    showcaseSub: string;
    attendance: string;
    goal: string;
  };
}

const ROW = 'flex items-center justify-between py-1.5 border-b border-[var(--border-subtle)]';
const LABEL = 'font-semibold text-[var(--text-primary)]';
const SUB = 'text-[11px] text-[var(--text-muted)]';
const XP = 'text-[11px] font-bold text-[var(--text-secondary)] whitespace-nowrap ml-2';

export default function ScoringInfoPopover({ i18n }: Props) {
  return (
    <InfoPopover title={i18n.title}>
      <div className="space-y-0">
        <div className={ROW}>
          <div><span className={LABEL}>🏆 {i18n.certSenior}</span><div className={SUB}>{i18n.certSeniorSub}</div></div>
          <span className={XP}>50 XP</span>
        </div>
        <div className={ROW}>
          <div><span className={LABEL}>🎓 {i18n.certCpmai}</span></div>
          <span className={XP}>45 XP</span>
        </div>
        <div className={ROW}>
          <div><span className={LABEL}>📋 {i18n.certMid}</span><div className={SUB}>{i18n.certMidSub}</div></div>
          <span className={XP}>40 XP</span>
        </div>
        <div className={ROW}>
          <div><span className={LABEL}>📌 {i18n.certPractitioner}</span><div className={SUB}>{i18n.certPractitionerSub}</div></div>
          <span className={XP}>35 XP</span>
        </div>
        <div className={ROW}>
          <div><span className={LABEL}>🟢 {i18n.certEntry}</span><div className={SUB}>{i18n.certEntrySub}</div></div>
          <span className={XP}>30 XP</span>
        </div>
        <div className={ROW}>
          <div><span className={LABEL}>⭐ {i18n.specialization}</span><div className={SUB}>{i18n.specializationSub}</div></div>
          <span className={XP}>25 XP</span>
        </div>
        <div className={ROW}>
          <div><span className={LABEL}>📚 {i18n.trail}</span><div className={SUB}>{i18n.trailSub}</div></div>
          <span className={XP}>20 XP</span>
        </div>
        <div className={ROW}>
          <div><span className={LABEL}>🧠 {i18n.knowledgeAiPm}</span><div className={SUB}>{i18n.knowledgeAiPmSub}</div></div>
          <span className={XP}>20 XP</span>
        </div>
        <div className={ROW}>
          <div><span className={LABEL}>📖 {i18n.course}</span></div>
          <span className={XP}>15 XP</span>
        </div>
        <div className={ROW}>
          <div><span className={LABEL}>🏅 {i18n.badge}</span></div>
          <span className={XP}>10 XP</span>
        </div>
        <div className={ROW}>
          <div><span className={LABEL}>🎤 {i18n.showcase}</span><div className={SUB}>{i18n.showcaseSub}</div></div>
          <span className={XP}>15–25 XP</span>
        </div>
        <div className={`${ROW} border-b-0`}>
          <div><span className={LABEL}>✅ {i18n.attendance}</span></div>
          <span className={XP}>10 XP</span>
        </div>
      </div>
      <div className="mt-3 pt-2 border-t border-[var(--border-default)] text-[11px] text-[var(--text-muted)] font-medium">
        {i18n.goal}
      </div>
    </InfoPopover>
  );
}
