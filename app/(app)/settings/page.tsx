import { AppShell } from "@/components/app-shell";
import { PrivacySettings } from "@/components/privacy-settings";

export default function SettingsPage() {
  return (
    <AppShell>
      <h1 className="text-3xl font-semibold">Settings</h1>
      <div className="mt-6"><PrivacySettings /></div>
    </AppShell>
  );
}
