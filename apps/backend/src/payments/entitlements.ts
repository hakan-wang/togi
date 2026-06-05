type PaymentInput = {
  paymentStatus: "paid" | "unpaid";
  product: "lifetime" | "subscription";
};

type Entitlement = {
  plan: "none" | "lifetime" | "subscription";
  active: boolean;
};

export function deriveEntitlement(input: PaymentInput): Entitlement {
  if (input.paymentStatus === "paid") {
    return { plan: input.product, active: true };
  }
  return { plan: "none", active: false };
}
