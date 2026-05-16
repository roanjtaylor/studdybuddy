import type { Metadata } from 'next';
import { Press_Start_2P, VT323 } from 'next/font/google';
import './globals.css';

const pixelHeading = Press_Start_2P({
  weight: '400',
  subsets: ['latin'],
  variable: '--font-pixel-heading',
  display: 'swap',
});

const pixelBody = VT323({
  weight: '400',
  subsets: ['latin'],
  variable: '--font-pixel-body',
  display: 'swap',
});

export const metadata: Metadata = {
  title: 'studybuddy — source-first learning',
  description: 'Find the canonical source. Skip the remixes.',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${pixelHeading.variable} ${pixelBody.variable}`}>
      <body>{children}</body>
    </html>
  );
}
