import { SubscriptionReplacementPolicy, ReplacementReadyContext } from './subscription-replacement.policy';
import { SubscriptionCancellationPolicy } from './subscription-cancellation.policy';

describe('Full-volume replacement accounting', () => {
  const policy = new SubscriptionReplacementPolicy();
  const context = (overrides = {}) => ({
    issuedSubscriptionId: 'old', studentId: 'student', payerStudentId: 'student',
    fundingMode: 'installment', purchaseReason: null, oldPackageId: 'package',
    oldStatus: 'active', oldVersion: 1, oldFinalPriceMinor: '800000',
    oldUnitCount: '8', priorConsumedValueMinor: '0', oldObligationMinor: '800000',
    oldCurrencyCode: 'RUB', legacyLessonsUsed: '0', usedUnits: '6', actualPaidMinor: '800000',
    reservedLessonCount: 0, reservedUnits: '0', reservedRows: [], futureLessonCount: 0, futureUnits: '0',
    newPackage: { id: 'package', version: 1, name: 'Eight', unitCount: '8',
      basePriceMinor: '800000', currencyCode: 'RUB', validityDays: 30, active: true, deletedAt: null },
    ...overrides,
  } as ReplacementReadyContext);

  it('replenishes eight units and charges only after crediting unused contract value', () => {
    const result = policy.calculate(context());
    expect(result).toMatchObject({ deltaMinor: 600000n, positionMinor: 600000n,
      usedValueMinor: 600000n, remainingValueMinor: 200000n });
    expect(policy.planReservations(context({ reservedRows: [{ reservationId: 'future', units: '8' }] })))
      .toMatchObject({ transferReservationIds: ['future'], releasedUnits: '0' });
  });

  it('allows a new full package smaller than historical consumption', () => {
    const ctx = context();
    ctx.newPackage = { ...ctx.newPackage, unitCount: '1', basePriceMinor: '100000' };
    expect(() => policy.assertContext(ctx)).not.toThrow();
    expect(policy.calculate(ctx)).toMatchObject({ deltaMinor: -100000n,
      positionMinor: -100000n, positionKind: 'overpayment' });
  });

  it('retains debt across repeated replacement instead of reusing spent payments', () => {
    expect(policy.calculate(context({ usedUnits: '0', priorConsumedValueMinor: '600000',
      oldObligationMinor: '1400000' }))).toMatchObject({ deltaMinor: 0n, positionMinor: 600000n });
  });

  it('values fractional unused units at the issued price with integer rounding', () => {
    expect(policy.calculate(context({ oldUnitCount: '3', usedUnits: '1', oldFinalPriceMinor: '1000',
      oldObligationMinor: '1000', actualPaidMinor: '1000' })))
      .toMatchObject({ usedValueMinor: 334n, remainingValueMinor: 666n, deltaMinor: 799334n });
  });

  it('preserves unpaid consumption and does not promise a refund of unreceived money', () => {
    const ctx = context({ actualPaidMinor: '100000' });
    ctx.newPackage = { ...ctx.newPackage, unitCount: '1', basePriceMinor: '100000' };
    expect(policy.calculate(ctx)).toMatchObject({ deltaMinor: -100000n,
      positionMinor: 600000n, positionKind: 'debt' });
  });

  it('rejects a preview generated under the old carry-used replacement rules', () => {
    const current = policy.createTokenPayload({ userId: 'actor', role: 'manager' }, context());
    const legacy = { ...current, issuedAtSeconds: 1, expiresAtSeconds: 2 };
    delete legacy.replacementMode;
    delete legacy.oldUnitCount;
    delete legacy.priorConsumedValueMinor;
    delete legacy.oldObligationMinor;
    expect(() => policy.assertPreviewCurrent(legacy, current)).toThrow('После предпросмотра изменились');
  });

  it('limits cancellation funding after replacing an originally personal-account purchase', () => {
    const cancellation = new SubscriptionCancellationPolicy();
    const result = cancellation.calculate({ package: { unitCount: '8' }, usedUnits: '0', reservedUnits: '0',
      finalMinor: '800000', actualPaidMinor: '800000', previousRefundMinor: '0',
      priorConsumedValueMinor: '600000', fullVolumeReplacement: true, fundingMode: 'personal_account',
    } as Parameters<typeof cancellation.calculate>[0]);
    expect(result.confirmedFundedMinor).toBe(200000n);
    expect(result.recommendedRefundMinor).toBe(200000n);
  });
});
