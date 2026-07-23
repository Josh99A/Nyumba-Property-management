export function isEntitlementPlanObject(value) {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}
