export type CalendarEvent = {
  id: string;
  title: string;
  startTime: string;
  endTime: string;
  description?: string;
};

export type CalendarService = {
  readEvents(userId: string, startTime: string, endTime: string): Promise<CalendarEvent[]>;
  createEvent(userId: string, event: Omit<CalendarEvent, "id">): Promise<CalendarEvent>;
  updateEvent(userId: string, id: string, event: Partial<Omit<CalendarEvent, "id">>): Promise<CalendarEvent>;
  deleteEvent(userId: string, id: string): Promise<void>;
  syncChanges(userId: string): Promise<{ synced: number }>;
};

export const createGoogleCalendarService = (): CalendarService => ({
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
});
