import { google, type calendar_v3 } from "googleapis";

export type CalendarEvent = {
  id: string;
  title: string;
  startTime: string;
  endTime: string;
  description?: string;
};

export type CalendarService = {
  createAuthorizationUrl(userId: string): string | null;
  readEvents(userId: string, startTime: string, endTime: string): Promise<CalendarEvent[]>;
  createEvent(userId: string, event: Omit<CalendarEvent, "id">): Promise<CalendarEvent>;
  updateEvent(userId: string, id: string, event: Partial<Omit<CalendarEvent, "id">>): Promise<CalendarEvent>;
  deleteEvent(userId: string, id: string): Promise<void>;
  syncChanges(userId: string): Promise<{ synced: number }>;
};

export type GoogleCalendarConfig = {
  clientId?: string;
  clientSecret?: string;
  redirectUri?: string;
};

const calendarScopes = ["https://www.googleapis.com/auth/calendar.events"];

const resolveConfig = (config: GoogleCalendarConfig = {}): GoogleCalendarConfig => ({
  clientId: config.clientId ?? process.env.GOOGLE_CALENDAR_CLIENT_ID,
  clientSecret: config.clientSecret ?? process.env.GOOGLE_CALENDAR_CLIENT_SECRET,
  redirectUri: config.redirectUri ?? process.env.GOOGLE_CALENDAR_REDIRECT_URI
});

const isConfigured = (config: GoogleCalendarConfig) => Boolean(config.clientId && config.clientSecret && config.redirectUri);

const createOAuthClient = (config: GoogleCalendarConfig) =>
  new google.auth.OAuth2(config.clientId, config.clientSecret, config.redirectUri);

export const mapGoogleCalendarEvent = (event: calendar_v3.Schema$Event): CalendarEvent => ({
  id: event.id ?? crypto.randomUUID(),
  title: event.summary ?? "Untitled event",
  startTime: event.start?.dateTime ?? event.start?.date ?? "",
  endTime: event.end?.dateTime ?? event.end?.date ?? "",
  description: event.description ?? undefined
});

export const createGoogleCalendarService = (inputConfig: GoogleCalendarConfig = {}): CalendarService => {
  const config = resolveConfig(inputConfig);

  return {
    createAuthorizationUrl(userId) {
      if (!isConfigured(config)) return null;

      return createOAuthClient(config).generateAuthUrl({
        access_type: "offline",
        prompt: "consent",
        scope: calendarScopes,
        state: userId
      });
    },

    async readEvents() {
    return [];
    },

    async createEvent(_userId, event) {
      return { id: crypto.randomUUID(), ...event };
    },

    async updateEvent(_userId, id, event) {
      return {
        id,
        title: event.title ?? "Updated event",
        startTime: event.startTime ?? new Date().toISOString(),
        endTime: event.endTime ?? new Date().toISOString(),
        description: event.description
      };
    },

    async deleteEvent() {},

    async syncChanges() {
      return { synced: 0 };
    }
  };
};
