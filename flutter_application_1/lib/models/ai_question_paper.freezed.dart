// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'ai_question_paper.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$AiQuestionPaperSource implements DiagnosticableTreeMixin {

 String get title; String get section; String get pages; String get note;
/// Create a copy of AiQuestionPaperSource
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AiQuestionPaperSourceCopyWith<AiQuestionPaperSource> get copyWith => _$AiQuestionPaperSourceCopyWithImpl<AiQuestionPaperSource>(this as AiQuestionPaperSource, _$identity);

  /// Serializes this AiQuestionPaperSource to a JSON map.
  Map<String, dynamic> toJson();

@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'AiQuestionPaperSource'))
    ..add(DiagnosticsProperty('title', title))..add(DiagnosticsProperty('section', section))..add(DiagnosticsProperty('pages', pages))..add(DiagnosticsProperty('note', note));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AiQuestionPaperSource&&(identical(other.title, title) || other.title == title)&&(identical(other.section, section) || other.section == section)&&(identical(other.pages, pages) || other.pages == pages)&&(identical(other.note, note) || other.note == note));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,title,section,pages,note);

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'AiQuestionPaperSource(title: $title, section: $section, pages: $pages, note: $note)';
}


}

/// @nodoc
abstract mixin class $AiQuestionPaperSourceCopyWith<$Res>  {
  factory $AiQuestionPaperSourceCopyWith(AiQuestionPaperSource value, $Res Function(AiQuestionPaperSource) _then) = _$AiQuestionPaperSourceCopyWithImpl;
@useResult
$Res call({
 String title, String section, String pages, String note
});




}
/// @nodoc
class _$AiQuestionPaperSourceCopyWithImpl<$Res>
    implements $AiQuestionPaperSourceCopyWith<$Res> {
  _$AiQuestionPaperSourceCopyWithImpl(this._self, this._then);

  final AiQuestionPaperSource _self;
  final $Res Function(AiQuestionPaperSource) _then;

/// Create a copy of AiQuestionPaperSource
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? title = null,Object? section = null,Object? pages = null,Object? note = null,}) {
  return _then(_self.copyWith(
title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,section: null == section ? _self.section : section // ignore: cast_nullable_to_non_nullable
as String,pages: null == pages ? _self.pages : pages // ignore: cast_nullable_to_non_nullable
as String,note: null == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [AiQuestionPaperSource].
extension AiQuestionPaperSourcePatterns on AiQuestionPaperSource {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AiQuestionPaperSource value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AiQuestionPaperSource() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AiQuestionPaperSource value)  $default,){
final _that = this;
switch (_that) {
case _AiQuestionPaperSource():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AiQuestionPaperSource value)?  $default,){
final _that = this;
switch (_that) {
case _AiQuestionPaperSource() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String title,  String section,  String pages,  String note)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AiQuestionPaperSource() when $default != null:
return $default(_that.title,_that.section,_that.pages,_that.note);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String title,  String section,  String pages,  String note)  $default,) {final _that = this;
switch (_that) {
case _AiQuestionPaperSource():
return $default(_that.title,_that.section,_that.pages,_that.note);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String title,  String section,  String pages,  String note)?  $default,) {final _that = this;
switch (_that) {
case _AiQuestionPaperSource() when $default != null:
return $default(_that.title,_that.section,_that.pages,_that.note);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _AiQuestionPaperSource with DiagnosticableTreeMixin implements AiQuestionPaperSource {
  const _AiQuestionPaperSource({this.title = '', this.section = '', this.pages = '', this.note = ''});
  factory _AiQuestionPaperSource.fromJson(Map<String, dynamic> json) => _$AiQuestionPaperSourceFromJson(json);

@override@JsonKey() final  String title;
@override@JsonKey() final  String section;
@override@JsonKey() final  String pages;
@override@JsonKey() final  String note;

/// Create a copy of AiQuestionPaperSource
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AiQuestionPaperSourceCopyWith<_AiQuestionPaperSource> get copyWith => __$AiQuestionPaperSourceCopyWithImpl<_AiQuestionPaperSource>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$AiQuestionPaperSourceToJson(this, );
}
@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'AiQuestionPaperSource'))
    ..add(DiagnosticsProperty('title', title))..add(DiagnosticsProperty('section', section))..add(DiagnosticsProperty('pages', pages))..add(DiagnosticsProperty('note', note));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AiQuestionPaperSource&&(identical(other.title, title) || other.title == title)&&(identical(other.section, section) || other.section == section)&&(identical(other.pages, pages) || other.pages == pages)&&(identical(other.note, note) || other.note == note));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,title,section,pages,note);

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'AiQuestionPaperSource(title: $title, section: $section, pages: $pages, note: $note)';
}


}

/// @nodoc
abstract mixin class _$AiQuestionPaperSourceCopyWith<$Res> implements $AiQuestionPaperSourceCopyWith<$Res> {
  factory _$AiQuestionPaperSourceCopyWith(_AiQuestionPaperSource value, $Res Function(_AiQuestionPaperSource) _then) = __$AiQuestionPaperSourceCopyWithImpl;
@override @useResult
$Res call({
 String title, String section, String pages, String note
});




}
/// @nodoc
class __$AiQuestionPaperSourceCopyWithImpl<$Res>
    implements _$AiQuestionPaperSourceCopyWith<$Res> {
  __$AiQuestionPaperSourceCopyWithImpl(this._self, this._then);

  final _AiQuestionPaperSource _self;
  final $Res Function(_AiQuestionPaperSource) _then;

/// Create a copy of AiQuestionPaperSource
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? title = null,Object? section = null,Object? pages = null,Object? note = null,}) {
  return _then(_AiQuestionPaperSource(
title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,section: null == section ? _self.section : section // ignore: cast_nullable_to_non_nullable
as String,pages: null == pages ? _self.pages : pages // ignore: cast_nullable_to_non_nullable
as String,note: null == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$AiQuestionPaperQuestion implements DiagnosticableTreeMixin {

 String get question; List<String> get options; int get correctIndex; String get explanation; AiQuestionPaperSource get source;
/// Create a copy of AiQuestionPaperQuestion
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AiQuestionPaperQuestionCopyWith<AiQuestionPaperQuestion> get copyWith => _$AiQuestionPaperQuestionCopyWithImpl<AiQuestionPaperQuestion>(this as AiQuestionPaperQuestion, _$identity);

  /// Serializes this AiQuestionPaperQuestion to a JSON map.
  Map<String, dynamic> toJson();

@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'AiQuestionPaperQuestion'))
    ..add(DiagnosticsProperty('question', question))..add(DiagnosticsProperty('options', options))..add(DiagnosticsProperty('correctIndex', correctIndex))..add(DiagnosticsProperty('explanation', explanation))..add(DiagnosticsProperty('source', source));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AiQuestionPaperQuestion&&(identical(other.question, question) || other.question == question)&&const DeepCollectionEquality().equals(other.options, options)&&(identical(other.correctIndex, correctIndex) || other.correctIndex == correctIndex)&&(identical(other.explanation, explanation) || other.explanation == explanation)&&(identical(other.source, source) || other.source == source));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,question,const DeepCollectionEquality().hash(options),correctIndex,explanation,source);

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'AiQuestionPaperQuestion(question: $question, options: $options, correctIndex: $correctIndex, explanation: $explanation, source: $source)';
}


}

/// @nodoc
abstract mixin class $AiQuestionPaperQuestionCopyWith<$Res>  {
  factory $AiQuestionPaperQuestionCopyWith(AiQuestionPaperQuestion value, $Res Function(AiQuestionPaperQuestion) _then) = _$AiQuestionPaperQuestionCopyWithImpl;
@useResult
$Res call({
 String question, List<String> options, int correctIndex, String explanation, AiQuestionPaperSource source
});


$AiQuestionPaperSourceCopyWith<$Res> get source;

}
/// @nodoc
class _$AiQuestionPaperQuestionCopyWithImpl<$Res>
    implements $AiQuestionPaperQuestionCopyWith<$Res> {
  _$AiQuestionPaperQuestionCopyWithImpl(this._self, this._then);

  final AiQuestionPaperQuestion _self;
  final $Res Function(AiQuestionPaperQuestion) _then;

/// Create a copy of AiQuestionPaperQuestion
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? question = null,Object? options = null,Object? correctIndex = null,Object? explanation = null,Object? source = null,}) {
  return _then(_self.copyWith(
question: null == question ? _self.question : question // ignore: cast_nullable_to_non_nullable
as String,options: null == options ? _self.options : options // ignore: cast_nullable_to_non_nullable
as List<String>,correctIndex: null == correctIndex ? _self.correctIndex : correctIndex // ignore: cast_nullable_to_non_nullable
as int,explanation: null == explanation ? _self.explanation : explanation // ignore: cast_nullable_to_non_nullable
as String,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as AiQuestionPaperSource,
  ));
}
/// Create a copy of AiQuestionPaperQuestion
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AiQuestionPaperSourceCopyWith<$Res> get source {
  
  return $AiQuestionPaperSourceCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}
}


/// Adds pattern-matching-related methods to [AiQuestionPaperQuestion].
extension AiQuestionPaperQuestionPatterns on AiQuestionPaperQuestion {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AiQuestionPaperQuestion value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AiQuestionPaperQuestion() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AiQuestionPaperQuestion value)  $default,){
final _that = this;
switch (_that) {
case _AiQuestionPaperQuestion():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AiQuestionPaperQuestion value)?  $default,){
final _that = this;
switch (_that) {
case _AiQuestionPaperQuestion() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String question,  List<String> options,  int correctIndex,  String explanation,  AiQuestionPaperSource source)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AiQuestionPaperQuestion() when $default != null:
return $default(_that.question,_that.options,_that.correctIndex,_that.explanation,_that.source);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String question,  List<String> options,  int correctIndex,  String explanation,  AiQuestionPaperSource source)  $default,) {final _that = this;
switch (_that) {
case _AiQuestionPaperQuestion():
return $default(_that.question,_that.options,_that.correctIndex,_that.explanation,_that.source);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String question,  List<String> options,  int correctIndex,  String explanation,  AiQuestionPaperSource source)?  $default,) {final _that = this;
switch (_that) {
case _AiQuestionPaperQuestion() when $default != null:
return $default(_that.question,_that.options,_that.correctIndex,_that.explanation,_that.source);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _AiQuestionPaperQuestion with DiagnosticableTreeMixin implements AiQuestionPaperQuestion {
   _AiQuestionPaperQuestion({required this.question, required final  List<String> options, required this.correctIndex, this.explanation = '', this.source = const AiQuestionPaperSource()}): assert(options.isNotEmpty, 'options must not be empty'),assert(correctIndex >= 0 && correctIndex < options.length, 'Invalid correctIndex for options length'),_options = options;
  factory _AiQuestionPaperQuestion.fromJson(Map<String, dynamic> json) => _$AiQuestionPaperQuestionFromJson(json);

@override final  String question;
 final  List<String> _options;
@override List<String> get options {
  if (_options is EqualUnmodifiableListView) return _options;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_options);
}

@override final  int correctIndex;
@override@JsonKey() final  String explanation;
@override@JsonKey() final  AiQuestionPaperSource source;

/// Create a copy of AiQuestionPaperQuestion
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AiQuestionPaperQuestionCopyWith<_AiQuestionPaperQuestion> get copyWith => __$AiQuestionPaperQuestionCopyWithImpl<_AiQuestionPaperQuestion>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$AiQuestionPaperQuestionToJson(this, );
}
@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'AiQuestionPaperQuestion'))
    ..add(DiagnosticsProperty('question', question))..add(DiagnosticsProperty('options', options))..add(DiagnosticsProperty('correctIndex', correctIndex))..add(DiagnosticsProperty('explanation', explanation))..add(DiagnosticsProperty('source', source));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AiQuestionPaperQuestion&&(identical(other.question, question) || other.question == question)&&const DeepCollectionEquality().equals(other._options, _options)&&(identical(other.correctIndex, correctIndex) || other.correctIndex == correctIndex)&&(identical(other.explanation, explanation) || other.explanation == explanation)&&(identical(other.source, source) || other.source == source));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,question,const DeepCollectionEquality().hash(_options),correctIndex,explanation,source);

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'AiQuestionPaperQuestion(question: $question, options: $options, correctIndex: $correctIndex, explanation: $explanation, source: $source)';
}


}

/// @nodoc
abstract mixin class _$AiQuestionPaperQuestionCopyWith<$Res> implements $AiQuestionPaperQuestionCopyWith<$Res> {
  factory _$AiQuestionPaperQuestionCopyWith(_AiQuestionPaperQuestion value, $Res Function(_AiQuestionPaperQuestion) _then) = __$AiQuestionPaperQuestionCopyWithImpl;
@override @useResult
$Res call({
 String question, List<String> options, int correctIndex, String explanation, AiQuestionPaperSource source
});


@override $AiQuestionPaperSourceCopyWith<$Res> get source;

}
/// @nodoc
class __$AiQuestionPaperQuestionCopyWithImpl<$Res>
    implements _$AiQuestionPaperQuestionCopyWith<$Res> {
  __$AiQuestionPaperQuestionCopyWithImpl(this._self, this._then);

  final _AiQuestionPaperQuestion _self;
  final $Res Function(_AiQuestionPaperQuestion) _then;

/// Create a copy of AiQuestionPaperQuestion
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? question = null,Object? options = null,Object? correctIndex = null,Object? explanation = null,Object? source = null,}) {
  return _then(_AiQuestionPaperQuestion(
question: null == question ? _self.question : question // ignore: cast_nullable_to_non_nullable
as String,options: null == options ? _self._options : options // ignore: cast_nullable_to_non_nullable
as List<String>,correctIndex: null == correctIndex ? _self.correctIndex : correctIndex // ignore: cast_nullable_to_non_nullable
as int,explanation: null == explanation ? _self.explanation : explanation // ignore: cast_nullable_to_non_nullable
as String,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as AiQuestionPaperSource,
  ));
}

/// Create a copy of AiQuestionPaperQuestion
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AiQuestionPaperSourceCopyWith<$Res> get source {
  
  return $AiQuestionPaperSourceCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}
}


/// @nodoc
mixin _$AiQuestionPaper implements DiagnosticableTreeMixin {

 String get title; String get subject; String get semester; String get branch; List<String> get instructions; List<AiQuestionPaperQuestion> get questions; DateTime get generatedAt; int get pyqCount;
/// Create a copy of AiQuestionPaper
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AiQuestionPaperCopyWith<AiQuestionPaper> get copyWith => _$AiQuestionPaperCopyWithImpl<AiQuestionPaper>(this as AiQuestionPaper, _$identity);

  /// Serializes this AiQuestionPaper to a JSON map.
  Map<String, dynamic> toJson();

@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'AiQuestionPaper'))
    ..add(DiagnosticsProperty('title', title))..add(DiagnosticsProperty('subject', subject))..add(DiagnosticsProperty('semester', semester))..add(DiagnosticsProperty('branch', branch))..add(DiagnosticsProperty('instructions', instructions))..add(DiagnosticsProperty('questions', questions))..add(DiagnosticsProperty('generatedAt', generatedAt))..add(DiagnosticsProperty('pyqCount', pyqCount));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AiQuestionPaper&&(identical(other.title, title) || other.title == title)&&(identical(other.subject, subject) || other.subject == subject)&&(identical(other.semester, semester) || other.semester == semester)&&(identical(other.branch, branch) || other.branch == branch)&&const DeepCollectionEquality().equals(other.instructions, instructions)&&const DeepCollectionEquality().equals(other.questions, questions)&&(identical(other.generatedAt, generatedAt) || other.generatedAt == generatedAt)&&(identical(other.pyqCount, pyqCount) || other.pyqCount == pyqCount));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,title,subject,semester,branch,const DeepCollectionEquality().hash(instructions),const DeepCollectionEquality().hash(questions),generatedAt,pyqCount);

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'AiQuestionPaper(title: $title, subject: $subject, semester: $semester, branch: $branch, instructions: $instructions, questions: $questions, generatedAt: $generatedAt, pyqCount: $pyqCount)';
}


}

/// @nodoc
abstract mixin class $AiQuestionPaperCopyWith<$Res>  {
  factory $AiQuestionPaperCopyWith(AiQuestionPaper value, $Res Function(AiQuestionPaper) _then) = _$AiQuestionPaperCopyWithImpl;
@useResult
$Res call({
 String title, String subject, String semester, String branch, List<String> instructions, List<AiQuestionPaperQuestion> questions, DateTime generatedAt, int pyqCount
});




}
/// @nodoc
class _$AiQuestionPaperCopyWithImpl<$Res>
    implements $AiQuestionPaperCopyWith<$Res> {
  _$AiQuestionPaperCopyWithImpl(this._self, this._then);

  final AiQuestionPaper _self;
  final $Res Function(AiQuestionPaper) _then;

/// Create a copy of AiQuestionPaper
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? title = null,Object? subject = null,Object? semester = null,Object? branch = null,Object? instructions = null,Object? questions = null,Object? generatedAt = null,Object? pyqCount = null,}) {
  return _then(_self.copyWith(
title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,subject: null == subject ? _self.subject : subject // ignore: cast_nullable_to_non_nullable
as String,semester: null == semester ? _self.semester : semester // ignore: cast_nullable_to_non_nullable
as String,branch: null == branch ? _self.branch : branch // ignore: cast_nullable_to_non_nullable
as String,instructions: null == instructions ? _self.instructions : instructions // ignore: cast_nullable_to_non_nullable
as List<String>,questions: null == questions ? _self.questions : questions // ignore: cast_nullable_to_non_nullable
as List<AiQuestionPaperQuestion>,generatedAt: null == generatedAt ? _self.generatedAt : generatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,pyqCount: null == pyqCount ? _self.pyqCount : pyqCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [AiQuestionPaper].
extension AiQuestionPaperPatterns on AiQuestionPaper {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AiQuestionPaper value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AiQuestionPaper() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AiQuestionPaper value)  $default,){
final _that = this;
switch (_that) {
case _AiQuestionPaper():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AiQuestionPaper value)?  $default,){
final _that = this;
switch (_that) {
case _AiQuestionPaper() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String title,  String subject,  String semester,  String branch,  List<String> instructions,  List<AiQuestionPaperQuestion> questions,  DateTime generatedAt,  int pyqCount)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AiQuestionPaper() when $default != null:
return $default(_that.title,_that.subject,_that.semester,_that.branch,_that.instructions,_that.questions,_that.generatedAt,_that.pyqCount);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String title,  String subject,  String semester,  String branch,  List<String> instructions,  List<AiQuestionPaperQuestion> questions,  DateTime generatedAt,  int pyqCount)  $default,) {final _that = this;
switch (_that) {
case _AiQuestionPaper():
return $default(_that.title,_that.subject,_that.semester,_that.branch,_that.instructions,_that.questions,_that.generatedAt,_that.pyqCount);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String title,  String subject,  String semester,  String branch,  List<String> instructions,  List<AiQuestionPaperQuestion> questions,  DateTime generatedAt,  int pyqCount)?  $default,) {final _that = this;
switch (_that) {
case _AiQuestionPaper() when $default != null:
return $default(_that.title,_that.subject,_that.semester,_that.branch,_that.instructions,_that.questions,_that.generatedAt,_that.pyqCount);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _AiQuestionPaper with DiagnosticableTreeMixin implements AiQuestionPaper {
  const _AiQuestionPaper({required this.title, required this.subject, required this.semester, required this.branch, required final  List<String> instructions, required final  List<AiQuestionPaperQuestion> questions, required this.generatedAt, required this.pyqCount}): _instructions = instructions,_questions = questions;
  factory _AiQuestionPaper.fromJson(Map<String, dynamic> json) => _$AiQuestionPaperFromJson(json);

@override final  String title;
@override final  String subject;
@override final  String semester;
@override final  String branch;
 final  List<String> _instructions;
@override List<String> get instructions {
  if (_instructions is EqualUnmodifiableListView) return _instructions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_instructions);
}

 final  List<AiQuestionPaperQuestion> _questions;
@override List<AiQuestionPaperQuestion> get questions {
  if (_questions is EqualUnmodifiableListView) return _questions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_questions);
}

@override final  DateTime generatedAt;
@override final  int pyqCount;

/// Create a copy of AiQuestionPaper
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AiQuestionPaperCopyWith<_AiQuestionPaper> get copyWith => __$AiQuestionPaperCopyWithImpl<_AiQuestionPaper>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$AiQuestionPaperToJson(this, );
}
@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'AiQuestionPaper'))
    ..add(DiagnosticsProperty('title', title))..add(DiagnosticsProperty('subject', subject))..add(DiagnosticsProperty('semester', semester))..add(DiagnosticsProperty('branch', branch))..add(DiagnosticsProperty('instructions', instructions))..add(DiagnosticsProperty('questions', questions))..add(DiagnosticsProperty('generatedAt', generatedAt))..add(DiagnosticsProperty('pyqCount', pyqCount));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AiQuestionPaper&&(identical(other.title, title) || other.title == title)&&(identical(other.subject, subject) || other.subject == subject)&&(identical(other.semester, semester) || other.semester == semester)&&(identical(other.branch, branch) || other.branch == branch)&&const DeepCollectionEquality().equals(other._instructions, _instructions)&&const DeepCollectionEquality().equals(other._questions, _questions)&&(identical(other.generatedAt, generatedAt) || other.generatedAt == generatedAt)&&(identical(other.pyqCount, pyqCount) || other.pyqCount == pyqCount));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,title,subject,semester,branch,const DeepCollectionEquality().hash(_instructions),const DeepCollectionEquality().hash(_questions),generatedAt,pyqCount);

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'AiQuestionPaper(title: $title, subject: $subject, semester: $semester, branch: $branch, instructions: $instructions, questions: $questions, generatedAt: $generatedAt, pyqCount: $pyqCount)';
}


}

/// @nodoc
abstract mixin class _$AiQuestionPaperCopyWith<$Res> implements $AiQuestionPaperCopyWith<$Res> {
  factory _$AiQuestionPaperCopyWith(_AiQuestionPaper value, $Res Function(_AiQuestionPaper) _then) = __$AiQuestionPaperCopyWithImpl;
@override @useResult
$Res call({
 String title, String subject, String semester, String branch, List<String> instructions, List<AiQuestionPaperQuestion> questions, DateTime generatedAt, int pyqCount
});




}
/// @nodoc
class __$AiQuestionPaperCopyWithImpl<$Res>
    implements _$AiQuestionPaperCopyWith<$Res> {
  __$AiQuestionPaperCopyWithImpl(this._self, this._then);

  final _AiQuestionPaper _self;
  final $Res Function(_AiQuestionPaper) _then;

/// Create a copy of AiQuestionPaper
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? title = null,Object? subject = null,Object? semester = null,Object? branch = null,Object? instructions = null,Object? questions = null,Object? generatedAt = null,Object? pyqCount = null,}) {
  return _then(_AiQuestionPaper(
title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,subject: null == subject ? _self.subject : subject // ignore: cast_nullable_to_non_nullable
as String,semester: null == semester ? _self.semester : semester // ignore: cast_nullable_to_non_nullable
as String,branch: null == branch ? _self.branch : branch // ignore: cast_nullable_to_non_nullable
as String,instructions: null == instructions ? _self._instructions : instructions // ignore: cast_nullable_to_non_nullable
as List<String>,questions: null == questions ? _self._questions : questions // ignore: cast_nullable_to_non_nullable
as List<AiQuestionPaperQuestion>,generatedAt: null == generatedAt ? _self.generatedAt : generatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,pyqCount: null == pyqCount ? _self.pyqCount : pyqCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
