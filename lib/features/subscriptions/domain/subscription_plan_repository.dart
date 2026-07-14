import 'subscription_plan_draft.dart';

abstract interface class SubscriptionPlanRepository {
  Stream<List<SubscriptionPlanDraft>> watchAll();
  Future<List<SubscriptionPlanDraft>> getAll();
  Future<SubscriptionPlanDraft?> getById(String id);
  Future<SubscriptionPlanDraft> create(CreatePlanDraftInput input);
  Future<SubscriptionPlanDraft> update(UpdatePlanDraftInput input);
}
