import { Analytics } from "@vercel/analytics/next";
import type { Metadata } from "next";
import { Dela_Gothic_One, M_PLUS_2 } from "next/font/google";
import { notFound } from "next/navigation";
import { hasLocale, NextIntlClientProvider } from "next-intl";
import { getTranslations, setRequestLocale } from "next-intl/server";
import type { ReactNode } from "react";
import { routing } from "@/i18n/routing";
import { languageAlternates, localePath, ogAlternateLocales, ogLocale } from "@/i18n/urls";
import "./globals.css";

// 見出しは角の立った太字、本文は癖の少ないゴシック。どちらも日本語を持つ。
// 日本語の書体は unicode-range で100件以上に割られていて、先読みすると
// 1ページで1.5MB読む。preload を切って、使う字の分だけ取らせる
const display = Dela_Gothic_One({
  display: "swap",
  preload: false,
  variable: "--font-display",
  weight: "400",
});

const body = M_PLUS_2({
  display: "swap",
  preload: false,
  variable: "--font-body",
  weight: ["400", "500", "700", "800"],
});

type LayoutProps = {
  children: ReactNode;
  params: Promise<{ locale: string }>;
};

export function generateStaticParams() {
  return routing.locales.map((locale) => ({ locale }));
}

export async function generateMetadata({
  params,
}: Omit<LayoutProps, "children">): Promise<Metadata> {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: "meta" });

  return {
    description: t("description"),
    alternates: {
      canonical: localePath(locale),
      languages: languageAlternates(),
    },
    metadataBase: new URL("https://owler.kkweb.io"),
    openGraph: {
      locale: ogLocale(locale),
      alternateLocale: ogAlternateLocales(locale),
      description: t("description"),
      url: localePath(locale),
      title: t("title"),
      type: "website",
    },
    twitter: {
      card: "summary_large_image",
      description: t("description"),
      title: t("title"),
    },
    title: t("title"),
  };
}

export default async function Layout({ children, params }: LayoutProps) {
  const { locale } = await params;

  if (!hasLocale(routing.locales, locale)) {
    notFound();
  }
  setRequestLocale(locale);

  return (
    <html className={`${display.variable} ${body.variable}`} lang={locale}>
      <body className="font-[family-name:var(--font-body)] antialiased">
        <NextIntlClientProvider>{children}</NextIntlClientProvider>
        <Analytics />
      </body>
    </html>
  );
}
