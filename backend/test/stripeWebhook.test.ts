import { describe, expect, it, vi } from "vitest";

vi.mock("../src/lib/stripe.js", () => ({
  constructEvent: vi.fn(),
}));

vi.mock("../src/lib/supabase.js", () => ({
  verifyJwt: vi.fn(),
  getProfile: vi.fn(),
  setPaidByUserId: vi.fn(),
  setPaidByCustomerId: vi.fn(),
}));

import { handler } from "../src/handler.js";
import { constructEvent } from "../src/lib/stripe.js";
import { setPaidByCustomerId, setPaidByUserId } from "../src/lib/supabase.js";
import { makeEvent } from "./helpers.js";

const constructEventMock = vi.mocked(constructEvent);
const setPaidByUserIdMock = vi.mocked(setPaidByUserId);
const setPaidByCustomerIdMock = vi.mocked(setPaidByCustomerId);

function webhookEvent(signature: string | undefined, raw: string) {
  return makeEvent({
    method: "POST",
    path: "/v1/stripe/webhook",
    headers: signature ? { "stripe-signature": signature } : {},
    body: raw,
  });
}

describe("POST /v1/stripe/webhook", () => {
  it("rejects a bad signature with 401 and does not touch Supabase", async () => {
    constructEventMock.mockImplementationOnce(() => {
      throw new Error("No signatures found matching the expected signature");
    });
    const res = await handler(webhookEvent("t=1,v1=bad", "{}"));
    expect(res.statusCode).toBe(401);
    expect(setPaidByUserIdMock).not.toHaveBeenCalled();
    expect(setPaidByCustomerIdMock).not.toHaveBeenCalled();
  });

  it("flips paid=true on checkout.session.completed", async () => {
    constructEventMock.mockReturnValueOnce({
      id: "evt_1",
      type: "checkout.session.completed",
      data: {
        object: {
          client_reference_id: "user-1",
          customer: "cus_123",
          metadata: { plan: "pro" },
        },
      },
    } as unknown as ReturnType<typeof constructEvent>);

    const res = await handler(webhookEvent("t=1,v1=ok", "{}"));

    expect(res.statusCode).toBe(200);
    expect(JSON.parse(res.body)).toEqual({ received: true });
    expect(setPaidByUserIdMock).toHaveBeenCalledWith("user-1", true, "pro", "cus_123");
  });

  it("flips paid=false on customer.subscription.deleted", async () => {
    constructEventMock.mockReturnValueOnce({
      id: "evt_2",
      type: "customer.subscription.deleted",
      data: { object: { customer: "cus_123", status: "canceled", items: { data: [] } } },
    } as unknown as ReturnType<typeof constructEvent>);

    const res = await handler(webhookEvent("t=1,v1=ok", "{}"));

    expect(res.statusCode).toBe(200);
    expect(setPaidByCustomerIdMock).toHaveBeenCalledWith("cus_123", false, null);
  });

  it("acknowledges unrelated events with 200 without writes", async () => {
    constructEventMock.mockReturnValueOnce({
      id: "evt_3",
      type: "payment_intent.created",
      data: { object: {} },
    } as unknown as ReturnType<typeof constructEvent>);

    const res = await handler(webhookEvent("t=1,v1=ok", "{}"));
    expect(res.statusCode).toBe(200);
    expect(setPaidByUserIdMock).not.toHaveBeenCalled();
    expect(setPaidByCustomerIdMock).not.toHaveBeenCalled();
  });
});
