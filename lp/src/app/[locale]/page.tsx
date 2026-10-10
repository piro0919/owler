import Image from "next/image";
import { getTranslations, setRequestLocale } from "next-intl/server";
import type { ReactNode } from "react";
import { Link } from "@/i18n/navigation";
import { LanguageSwitch } from "./language-switch";

const REPO = "https://github.com/piro0919/owler";
const DOWNLOAD = `${REPO}/releases/latest`;
const BREW = "brew install --cask piro0919/tap/owler";

type Item = { title: string; body: string };

type PageProps = {
  params: Promise<{ locale: string }>;
};

/// 手本は Vercel のボタン。黒い塗りと、細い線の2種類だけ
function PrimaryButton({ children, href }: { children: ReactNode; href: string }) {
  return (
    <a
      className="inline-flex h-11 items-center rounded-full bg-ink px-5 font-medium text-[15px] text-bg transition hover:opacity-85"
      href={href}
    >
      {children}
    </a>
  );
}

function SecondaryButton({ children, href }: { children: ReactNode; href: string }) {
  return (
    <a
      className="inline-flex h-11 items-center rounded-full border border-line bg-card px-5 font-medium text-[15px] transition hover:border-muted"
      href={href}
    >
      {children}
    </a>
  );
}

/// 改行の位置を文言の側で決めた見出し。ブラウザ任せにすると「見／張る」のように語の途中で割れる。
/// 狭い画面では1行に収まらないので、固定せずに流す（固定すると「keeps／watch」と細切れになる）
/// 行のあいだの空白は英語だけ。日本語は「は、」のあとに空白を入れない
function Lines({ lines, spaced }: { lines: string[]; spaced: boolean }) {
  return lines.map((line, index) => (
    <span className="sm:block" key={line}>
      {spaced && index > 0 && <span className="sm:hidden"> </span>}
      {line}
    </span>
  ));
}

/// ターミナルに貼る1行。横に長いので、狭い画面では中で横に流す
function Command({ children }: { children: string }) {
  return (
    <pre className="overflow-x-auto rounded-lg border border-line bg-card px-4 py-3 font-mono text-[13px] leading-relaxed">
      <code>
        <span className="select-none text-muted">$ </span>
        {children}
      </code>
    </pre>
  );
}

export default async function Page({ params }: PageProps) {
  const { locale } = await params;
  setRequestLocale(locale);

  const t = await getTranslations();
  const tagline = t.raw("hero.tagline") as string[];
  const lead = t.raw("hero.lead") as string[];
  const points = t.raw("hero.points") as string[];
  const items = t.raw("product.items") as Item[];
  const steps = t.raw("install.steps") as Item[];
  const shot = locale === "ja" ? "/shot-ja.png" : "/shot-en.png";

  return (
    <div className="mx-auto max-w-6xl px-6">
      {/* 上の帯 */}
      <header className="flex h-16 items-center justify-between">
        <div className="flex items-center gap-2.5">
          <Image alt="" className="h-7 w-7" height={56} priority src="/icon.png" width={56} />
          <span className="font-semibold text-[17px] tracking-tight">Owler</span>
        </div>
        <div className="flex items-center gap-5">
          <LanguageSwitch />
          <a className="hidden text-muted text-sm transition hover:text-ink sm:inline" href={REPO}>
            GitHub
          </a>
        </div>
      </header>

      {/* 見出し。左に見出しと1行とボタン、右に描き起こした絵 */}
      <section className="grid items-center gap-12 py-16 lg:grid-cols-[1fr_1.1fr] lg:py-24">
        <div className="flex flex-col gap-7">
          <h1 className="display text-5xl sm:text-6xl">
            <Lines lines={tagline} spaced={locale !== "ja"} />
          </h1>
          <p className="text-[19px] text-muted leading-relaxed">
            <Lines lines={lead} spaced={locale !== "ja"} />
          </p>
          <div className="flex flex-wrap gap-3">
            <PrimaryButton href={DOWNLOAD}>{t("hero.download")}</PrimaryButton>
            <SecondaryButton href={REPO}>GitHub</SecondaryButton>
          </div>
          <ul className="flex flex-wrap gap-x-5 gap-y-2 text-muted text-sm">
            {points.map((point) => (
              <li className="flex items-center gap-2" key={point}>
                <span className="h-1.5 w-1.5 rounded-full bg-amber" />
                {point}
              </li>
            ))}
          </ul>
          <p className="text-muted text-xs">{t("hero.requirement")}</p>
        </div>
        <div className="overflow-hidden rounded-2xl border border-line shadow-[0_30px_60px_-30px_rgba(0,0,0,0.35)]">
          <Image
            alt=""
            className="w-full"
            height={1024}
            priority
            sizes="(min-width: 1024px) 50vw, 100vw"
            src="/hero.png"
            width={1536}
          />
        </div>
      </section>

      {/* 何をするアプリか。枠に入れた窓の写真と、項目名だけの短いリスト */}
      <section className="flex flex-col gap-12 py-20">
        <h2 className="display max-w-3xl text-balance text-4xl sm:text-5xl">
          {t("product.title")}
        </h2>
        <div className="grid items-start gap-12 lg:grid-cols-[1.6fr_1fr]">
          <div className="overflow-hidden rounded-xl border border-line bg-card p-2 shadow-[0_1px_2px_rgba(0,0,0,0.04)]">
            <Image
              alt=""
              className="w-full rounded-lg"
              height={1200}
              sizes="(min-width: 1024px) 60vw, 100vw"
              src={shot}
              width={1920}
            />
          </div>
          <div className="flex flex-col gap-8 lg:pt-4">
            {/* 黒と灰色の2段。1つの段落に続けて流すと、灰色の頭が語の途中で折り返される */}
            <p className="flex flex-col gap-1 text-[22px] leading-snug tracking-tight">
              <span>{t("product.statement")}</span>
              <span className="text-muted">{t("product.statementMuted")}</span>
            </p>
            <div className="flex flex-col gap-4">
              <p className="text-muted text-sm">{t("product.label")}</p>
              <dl className="flex flex-col gap-4">
                {items.map((item) => (
                  <div className="flex flex-col gap-1" key={item.title}>
                    <dt className="font-medium text-[15px]">{item.title}</dt>
                    <dd className="text-muted text-sm leading-relaxed">{item.body}</dd>
                  </div>
                ))}
              </dl>
            </div>
          </div>
        </div>
      </section>

      {/* 入れ方 */}
      <section className="flex flex-col items-center gap-12 py-24 text-center">
        <h2 className="display max-w-3xl text-balance text-4xl sm:text-5xl">
          {t("install.title")}
        </h2>
        <ol className="grid w-full gap-px overflow-hidden rounded-xl border border-line bg-line text-left sm:grid-cols-3">
          {steps.map((step, index) => (
            <li className="flex flex-col gap-3 bg-card p-6" key={step.title}>
              <span className="font-mono text-muted text-sm">
                {String(index + 1).padStart(2, "0")}
              </span>
              <h3 className="font-medium text-[17px]">{step.title}</h3>
              <p className="text-muted text-sm leading-relaxed">{step.body}</p>
            </li>
          ))}
        </ol>
        <div className="w-full max-w-xl">
          <Command>{BREW}</Command>
        </div>
        <p className="max-w-xl text-muted text-sm leading-relaxed">{t("install.accessibility")}</p>
        <PrimaryButton href={DOWNLOAD}>{t("install.cta")}</PrimaryButton>
      </section>

      <footer className="flex flex-col items-center justify-between gap-4 border-line border-t py-10 text-muted text-sm sm:flex-row">
        <span>Owler</span>
        <div className="flex gap-6">
          <a className="transition hover:text-ink" href={REPO}>
            {t("footer.source")}
          </a>
          <a className="transition hover:text-ink" href={`${REPO}/releases`}>
            {t("footer.releases")}
          </a>
          <Link className="transition hover:text-ink" href="/privacy">
            {t("footer.privacy")}
          </Link>
          <a className="transition hover:text-ink" href="https://buymeacoffee.com/piro0919">
            Buy Me a Coffee
          </a>
        </div>
      </footer>
    </div>
  );
}
