// Content feedback model — polymorphic across all content types.
// Mirrors pibrief/core/domain/models/post_feedback.dart; kept in sync by hand.

enum ContentTargetType {
  post('post'),
  scheme('scheme'),
  entity('entity'),
  legalRef('legal_ref'),
  question('question'),
  app('app');

  const ContentTargetType(this.value);
  final String value;

  static ContentTargetType fromValue(String v) =>
      ContentTargetType.values.firstWhere((e) => e.value == v,
          orElse: () => ContentTargetType.post);

  String get label => switch (this) {
        ContentTargetType.post => 'Post',
        ContentTargetType.scheme => 'Scheme',
        ContentTargetType.entity => 'Entity',
        ContentTargetType.legalRef => 'Legal Ref',
        ContentTargetType.question => 'Question',
        ContentTargetType.app => 'App',
      };
}

enum FeedbackType {
  relevanceTooHigh('relevance_too_high', 'Score too high'),
  relevanceTooLow('relevance_too_low', 'Score too low'),
  syllabusWrong('syllabus_wrong', 'Syllabus wrong'),
  schemeMissed('scheme_missed', 'Scheme missed'),
  summaryPoor('summary_poor', 'Summary poor'),
  notUseful('not_useful', 'Not useful'),
  incorrectInfo('incorrect_info', 'Incorrect info'),
  outdated('outdated', 'Outdated'),
  missingDetail('missing_detail', 'Missing detail'),
  wrongClassification('wrong_classification', 'Wrong classification'),
  other('other', 'Other');

  const FeedbackType(this.value, this.label);
  final String value;
  final String label;

  static FeedbackType fromValue(String v) =>
      FeedbackType.values.firstWhere((e) => e.value == v,
          orElse: () => FeedbackType.other);
}

class AdminFeedbackItem {
  final String id;
  final ContentTargetType targetType;
  final String targetId;
  final String targetLabel;
  final String userId;
  final FeedbackType feedbackType;
  final String? note;
  final String status;
  final DateTime createdAt;

  const AdminFeedbackItem({
    required this.id,
    required this.targetType,
    required this.targetId,
    required this.targetLabel,
    required this.userId,
    required this.feedbackType,
    this.note,
    required this.status,
    required this.createdAt,
  });

  bool get isPending => status == 'pending';

  AdminFeedbackItem copyWith({String? status}) => AdminFeedbackItem(
        id: id,
        targetType: targetType,
        targetId: targetId,
        targetLabel: targetLabel,
        userId: userId,
        feedbackType: feedbackType,
        note: note,
        status: status ?? this.status,
        createdAt: createdAt,
      );
}
