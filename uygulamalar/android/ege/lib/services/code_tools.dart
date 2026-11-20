import 'dart:typed_data';

import 'package:flutter/painting.dart';

/// Language detection, lightweight syntax highlighting and line diffs for the
/// PC code viewer.
class CodeLang {
  static String detect(String path) {
    final name = path.split(RegExp(r'[\\/]')).last.toLowerCase();
    final dot = name.lastIndexOf('.');
    final ext = dot < 0 ? '' : name.substring(dot + 1);
    if (name == 'dockerfile') return 'shell';
    switch (ext) {
      case 'dart':
        return 'dart';
      case 'kt':
      case 'kts':
        return 'kotlin';
      case 'java':
      case 'gradle':
        return 'java';
      case 'py':
        return 'python';
      case 'js':
      case 'mjs':
      case 'cjs':
      case 'jsx':
        return 'javascript';
      case 'ts':
      case 'tsx':
      case 'vue':
        return 'typescript';
      case 'json':
      case 'lock':
        return 'json';
      case 'yaml':
      case 'yml':
        return 'yaml';
      case 'toml':
      case 'ini':
      case 'cfg':
      case 'properties':
      case 'env':
        return 'ini';
      case 'md':
        return 'markdown';
      case 'xml':
      case 'html':
      case 'htm':
      case 'svg':
      case 'plist':
      case 'iml':
        return 'xml';
      case 'css':
      case 'scss':
        return 'css';
      case 'sh':
      case 'bash':
        return 'shell';
      case 'ps1':
      case 'psm1':
        return 'powershell';
      case 'bat':
      case 'cmd':
        return 'batch';
      case 'c':
      case 'h':
      case 'cpp':
      case 'hpp':
      case 'cs':
      case 'go':
      case 'rs':
      case 'swift':
      case 'm':
        return 'c';
      case 'sql':
        return 'sql';
      default:
        return 'text';
    }
  }

  static String label(String lang) => switch (lang) {
        'dart' => 'Dart',
        'kotlin' => 'Kotlin',
        'java' => 'Java / Gradle',
        'python' => 'Python',
        'javascript' => 'JavaScript',
        'typescript' => 'TypeScript',
        'json' => 'JSON',
        'yaml' => 'YAML',
        'ini' => 'Yapılandırma',
        'markdown' => 'Markdown',
        'xml' => 'XML / HTML',
        'css' => 'CSS',
        'shell' => 'Shell',
        'powershell' => 'PowerShell',
        'batch' => 'Batch',
        'c' => 'C ailesi',
        'sql' => 'SQL',
        _ => 'Metin',
      };
}

class CodePalette {
  static const base = Color(0xFFD5DEEA);
  static const keyword = Color(0xFFC792EA);
  static const string = Color(0xFFA5E887);
  static const comment = Color(0xFF64748B);
  static const number = Color(0xFFF9C66B);
  static const type = Color(0xFF6EE7F9);
  static const function = Color(0xFF82AAFF);
  static const annotation = Color(0xFFF78C9C);
  static const punctuation = Color(0xFF94A3B8);
  static const key = Color(0xFF7DD3FC);
}

class CodeHighlighter {
  static const _kw = {
    'dart': 'abstract as assert async await base break case catch class const continue covariant default deferred do dynamic else enum export extends extension external factory false final finally for Function get hide if implements import in interface is late library mixin new null of on operator part required rethrow return sealed set show static super switch sync this throw true try typedef var void when while with yield',
    'kotlin': 'abstract actual annotation as break by catch class companion const constructor continue crossinline data do else enum expect external false final finally for fun get if import in infix init inline inner interface internal is lateinit noinline null object open operator out override package private protected public reified return sealed set super suspend this throw true try typealias val var vararg when where while',
    'java': 'abstract assert boolean break byte case catch char class const continue default do double else enum extends final finally float for goto if implements import instanceof int interface long native new null package private protected public return short static strictfp super switch synchronized this throw throws transient try void volatile while true false var plugins id apply dependencies implementation android',
    'python': 'and as assert async await break class continue def del elif else except False finally for from global if import in is lambda None nonlocal not or pass raise return True try while with yield self match case',
    'javascript': 'async await break case catch class const continue debugger default delete do else export extends false finally for function if import in instanceof let new null return super switch this throw true try typeof undefined var void while with yield of',
    'typescript': 'abstract any as async await boolean break case catch class const constructor continue declare default delete do else enum export extends false finally for from function get if implements import in instanceof interface is keyof let module namespace never new null number object of private protected public readonly return set static string super switch this throw true try type typeof undefined unknown var void while yield',
    'c': 'auto break case char const continue default do double else enum extern float for goto if inline int long register return short signed sizeof static struct switch typedef union unsigned void volatile while class public private protected namespace using new delete true false null nullptr fn let mut impl pub use func package var type struct interface go defer',
    'shell': 'if then else elif fi for while do done case esac function in return export local echo exit',
    'powershell': 'begin break catch class continue data do dynamicparam else elseif end exit filter finally for foreach from function if in param process return switch throw trap try until using var while true false null',
    'batch': 'echo set if else goto call exit for in do not exist pause rem setlocal endlocal',
    'sql': 'select from where insert into values update set delete create table index view drop alter add join left right inner outer on group by order having limit offset and or not null as distinct union all primary key foreign references',
    'css': 'important media import from to',
    'yaml': 'true false null yes no on off',
    'json': 'true false null',
  };

  static final Map<String, Set<String>> _kwCache = {};

  static Set<String> _keywords(String lang) => _kwCache.putIfAbsent(
        lang,
        () => (_kw[lang] ?? '').split(' ').where((e) => e.isNotEmpty).toSet(),
      );

  static String? _lineComment(String lang) => switch (lang) {
        'python' || 'shell' || 'powershell' || 'yaml' || 'ini' => '#',
        'sql' => '--',
        'batch' => '::',
        'dart' ||
        'kotlin' ||
        'java' ||
        'javascript' ||
        'typescript' ||
        'c' ||
        'css' =>
          '//',
        _ => null,
      };

  static final _num = RegExp(r'^(0x[0-9a-fA-F_]+|\d[\d_]*(\.\d+)?([eE][+-]?\d+)?)');
  static final _ident = RegExp(r'^[A-Za-z_$][\w$]*');

  /// Highlights [code] line by line. Multi-line block comments and triple
  /// quoted strings are tracked across lines.
  static List<TextSpan> highlightLines(
    List<String> lines,
    String lang, {
    int startLine = 0,
    int? endLine,
  }) {
    final out = <TextSpan>[];
    final end = (endLine ?? lines.length).clamp(0, lines.length);
    var state = _State();
    // Fast-forward state to the start line.
    for (var i = 0; i < startLine && i < lines.length; i++) {
      state = _scan(lines[i], lang, state, null);
    }
    for (var i = startLine; i < end; i++) {
      final spans = <TextSpan>[];
      state = _scan(lines[i], lang, state, spans);
      out.add(TextSpan(children: spans));
    }
    return out;
  }

  static TextSpan highlightLine(String line, String lang) {
    final spans = <TextSpan>[];
    _scan(line, lang, _State(), spans);
    return TextSpan(children: spans);
  }

  static _State _scan(String line, String lang, _State st, List<TextSpan>? out) {
    void emit(String text, Color color, {bool italic = false, bool bold = false}) {
      if (out == null || text.isEmpty) return;
      out.add(TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontStyle: italic ? FontStyle.italic : null,
          fontWeight: bold ? FontWeight.w600 : null,
        ),
      ));
    }

    if (lang == 'text') {
      emit(line, CodePalette.base);
      return st;
    }
    if (lang == 'markdown') {
      final t = line.trimLeft();
      if (t.startsWith('```')) {
        emit(line, CodePalette.annotation);
        return _State(inFence: !st.inFence);
      }
      if (st.inFence) {
        emit(line, CodePalette.string);
        return st;
      }
      if (t.startsWith('#')) {
        emit(line, CodePalette.type, bold: true);
      } else if (t.startsWith('- ') || t.startsWith('* ') || RegExp(r'^\d+\. ').hasMatch(t)) {
        emit(line, CodePalette.base);
      } else {
        emit(line, CodePalette.base);
      }
      return st;
    }

    final kws = _keywords(lang);
    final lc = _lineComment(lang);
    final cLike = const {'dart', 'kotlin', 'java', 'javascript', 'typescript', 'c', 'css'}.contains(lang);
    var i = 0;
    var blockEnd = st.blockEnd;
    final n = line.length;

    if (blockEnd != null) {
      final idx = line.indexOf(blockEnd);
      if (idx < 0) {
        emit(line, st.blockIsString ? CodePalette.string : CodePalette.comment, italic: !st.blockIsString);
        return st;
      }
      final stop = idx + blockEnd.length;
      emit(line.substring(0, stop), st.blockIsString ? CodePalette.string : CodePalette.comment, italic: !st.blockIsString);
      i = stop;
      blockEnd = null;
    }

    final buf = StringBuffer();
    void flushPlain() {
      if (buf.isNotEmpty) {
        emit(buf.toString(), CodePalette.punctuation);
        buf.clear();
      }
    }

    while (i < n) {
      final rest = line.substring(i);
      final ch = line[i];

      // XML / HTML
      if (lang == 'xml') {
        if (rest.startsWith('<!--')) {
          flushPlain();
          final e = line.indexOf('-->', i + 4);
          if (e < 0) {
            emit(rest, CodePalette.comment, italic: true);
            return _State(blockEnd: '-->');
          }
          emit(line.substring(i, e + 3), CodePalette.comment, italic: true);
          i = e + 3;
          continue;
        }
        if (ch == '<') {
          flushPlain();
          final m = RegExp(r'^</?[\w:.-]+').firstMatch(rest);
          if (m != null) {
            emit(m.group(0)!, CodePalette.keyword);
            i += m.group(0)!.length;
            continue;
          }
        }
        if (ch == '"' || ch == "'") {
          flushPlain();
          final e = line.indexOf(ch, i + 1);
          final stop = e < 0 ? n : e + 1;
          emit(line.substring(i, stop), CodePalette.string);
          i = stop;
          continue;
        }
        final attr = RegExp(r'^[\w:.-]+(?==)').firstMatch(rest);
        if (attr != null) {
          flushPlain();
          emit(attr.group(0)!, CodePalette.function);
          i += attr.group(0)!.length;
          continue;
        }
        buf.write(ch);
        i++;
        continue;
      }

      // Comments
      if (lc != null && rest.startsWith(lc)) {
        flushPlain();
        emit(rest, CodePalette.comment, italic: true);
        return _State();
      }
      if (lang == 'batch' && rest.toLowerCase().startsWith('rem ')) {
        flushPlain();
        emit(rest, CodePalette.comment, italic: true);
        return _State();
      }
      if (cLike && rest.startsWith('/*')) {
        flushPlain();
        final e = line.indexOf('*/', i + 2);
        if (e < 0) {
          emit(rest, CodePalette.comment, italic: true);
          return _State(blockEnd: '*/');
        }
        emit(line.substring(i, e + 2), CodePalette.comment, italic: true);
        i = e + 2;
        continue;
      }
      if (lang == 'powershell' && rest.startsWith('<#')) {
        flushPlain();
        final e = line.indexOf('#>', i + 2);
        if (e < 0) {
          emit(rest, CodePalette.comment, italic: true);
          return _State(blockEnd: '#>');
        }
        emit(line.substring(i, e + 2), CodePalette.comment, italic: true);
        i = e + 2;
        continue;
      }

      // Strings
      if ((lang == 'python' || lang == 'dart' || lang == 'kotlin') &&
          (rest.startsWith('"""') || rest.startsWith("'''"))) {
        flushPlain();
        final q = rest.substring(0, 3);
        final e = line.indexOf(q, i + 3);
        if (e < 0) {
          emit(rest, CodePalette.string);
          return _State(blockEnd: q, blockIsString: true);
        }
        emit(line.substring(i, e + 3), CodePalette.string);
        i = e + 3;
        continue;
      }
      if (ch == '"' || ch == "'" || (ch == '`' && (lang == 'javascript' || lang == 'typescript' || lang == 'shell'))) {
        flushPlain();
        var j = i + 1;
        while (j < n) {
          if (line[j] == '\\') {
            j += 2;
            continue;
          }
          if (line[j] == ch) break;
          j++;
        }
        final stop = j >= n ? n : j + 1;
        final str = line.substring(i, stop);
        if (lang == 'json' || lang == 'yaml') {
          final after = line.substring(stop).trimLeft();
          emit(str, after.startsWith(':') ? CodePalette.key : CodePalette.string);
        } else {
          emit(str, CodePalette.string);
        }
        i = stop;
        continue;
      }

      // Annotations / decorators / variables
      if (ch == '@' && i + 1 < n && RegExp(r'[A-Za-z]').hasMatch(line[i + 1])) {
        flushPlain();
        final m = _ident.firstMatch(line.substring(i + 1));
        final len = 1 + (m?.group(0)?.length ?? 0);
        emit(line.substring(i, i + len), CodePalette.annotation);
        i += len;
        continue;
      }
      if (ch == r'$' && (lang == 'powershell' || lang == 'shell')) {
        flushPlain();
        final m = RegExp(r'^\$[\w:{}]+').firstMatch(rest);
        final len = m?.group(0)?.length ?? 1;
        emit(line.substring(i, i + len), CodePalette.type);
        i += len;
        continue;
      }

      // YAML / INI keys
      if ((lang == 'yaml' || lang == 'ini') && buf.toString().trim().isEmpty) {
        final m = RegExp(r'^[\w.\-\[\] ]+(?=\s*[:=])').firstMatch(rest);
        if (m != null && m.start == 0) {
          flushPlain();
          emit(m.group(0)!, CodePalette.key);
          i += m.group(0)!.length;
          continue;
        }
      }

      // Numbers
      if (RegExp(r'\d').hasMatch(ch) && (i == 0 || !RegExp(r'[\w$]').hasMatch(line[i - 1]))) {
        final m = _num.firstMatch(rest);
        if (m != null) {
          flushPlain();
          emit(m.group(0)!, CodePalette.number);
          i += m.group(0)!.length;
          continue;
        }
      }

      // Identifiers
      final m = _ident.firstMatch(rest);
      if (m != null) {
        flushPlain();
        final word = m.group(0)!;
        final after = i + word.length < n ? line[i + word.length] : '';
        final kwHit = lang == 'sql' || lang == 'batch'
            ? kws.contains(word.toLowerCase())
            : lang == 'powershell'
                ? kws.contains(word.toLowerCase())
                : kws.contains(word);
        if (kwHit) {
          emit(word, CodePalette.keyword, bold: true);
        } else if (RegExp(r'^[A-Z][a-z0-9]').hasMatch(word) && lang != 'sql') {
          emit(word, CodePalette.type);
        } else if (after == '(') {
          emit(word, CodePalette.function);
        } else {
          emit(word, CodePalette.base);
        }
        i += word.length;
        continue;
      }

      buf.write(ch);
      i++;
    }
    flushPlain();
    return _State(blockEnd: blockEnd);
  }
}

class _State {
  final String? blockEnd;
  final bool blockIsString;
  final bool inFence;

  _State({this.blockEnd, this.blockIsString = false, this.inFence = false});
}

enum DiffKind { same, add, del }

class DiffLine {
  final DiffKind kind;
  final String text;

  /// 1-based line numbers (0 when not applicable).
  final int oldNo;
  final int newNo;

  const DiffLine(this.kind, this.text, this.oldNo, this.newNo);
}

class LineDiff {
  /// Myers O(ND) line diff with common prefix/suffix trimming.
  static List<DiffLine> compute(String oldText, String newText, {int maxD = 3000}) {
    final a = oldText.split('\n');
    final b = newText.split('\n');
    var pre = 0;
    while (pre < a.length && pre < b.length && a[pre] == b[pre]) {
      pre++;
    }
    var suf = 0;
    while (suf < a.length - pre &&
        suf < b.length - pre &&
        a[a.length - 1 - suf] == b[b.length - 1 - suf]) {
      suf++;
    }
    final am = a.sublist(pre, a.length - suf);
    final bm = b.sublist(pre, b.length - suf);
    final out = <DiffLine>[];
    for (var i = 0; i < pre; i++) {
      out.add(DiffLine(DiffKind.same, a[i], i + 1, i + 1));
    }
    out.addAll(_myers(am, bm, pre, maxD));
    for (var k = 0; k < suf; k++) {
      final ai = a.length - suf + k;
      final bi = b.length - suf + k;
      out.add(DiffLine(DiffKind.same, a[ai], ai + 1, bi + 1));
    }
    return out;
  }

  static List<DiffLine> _myers(List<String> a, List<String> b, int offset, int maxD) {
    final n = a.length;
    final m = b.length;
    if (n == 0 && m == 0) return const [];
    if (n == 0) {
      return [for (var j = 0; j < m; j++) DiffLine(DiffKind.add, b[j], 0, offset + j + 1)];
    }
    if (m == 0) {
      return [for (var i = 0; i < n; i++) DiffLine(DiffKind.del, a[i], offset + i + 1, 0)];
    }
    final max = n + m;
    final size = 2 * max + 1;
    // Keep the saved traces under ~24 MB (6M Int32 values).
    final memCap = (6000000 ~/ size).clamp(32, maxD);
    final limit = max < memCap ? max : memCap;
    var v = Int32List(size);
    final trace = <Int32List>[];
    var found = false;
    for (var d = 0; d <= limit; d++) {
      trace.add(Int32List.fromList(v));
      for (var k = -d; k <= d; k += 2) {
        int x;
        if (k == -d || (k != d && v[max + k - 1] < v[max + k + 1])) {
          x = v[max + k + 1];
        } else {
          x = v[max + k - 1] + 1;
        }
        var y = x - k;
        while (x < n && y < m && a[x] == b[y]) {
          x++;
          y++;
        }
        v[max + k] = x;
        if (x >= n && y >= m) {
          found = true;
          break;
        }
      }
      if (found) break;
    }
    if (!found) {
      // Too many differences: show as full replacement.
      return [
        for (var i = 0; i < n; i++) DiffLine(DiffKind.del, a[i], offset + i + 1, 0),
        for (var j = 0; j < m; j++) DiffLine(DiffKind.add, b[j], 0, offset + j + 1),
      ];
    }
    final rev = <DiffLine>[];
    var x = n;
    var y = m;
    for (var d = trace.length - 1; d >= 0; d--) {
      final vd = trace[d];
      final k = x - y;
      int prevK;
      if (k == -d || (k != d && vd[max + k - 1] < vd[max + k + 1])) {
        prevK = k + 1;
      } else {
        prevK = k - 1;
      }
      final prevX = vd[max + prevK];
      final prevY = prevX - prevK;
      while (x > prevX && y > prevY) {
        rev.add(DiffLine(DiffKind.same, a[x - 1], offset + x, offset + y));
        x--;
        y--;
      }
      if (d > 0) {
        if (x == prevX) {
          rev.add(DiffLine(DiffKind.add, b[y - 1], 0, offset + y));
          y--;
        } else {
          rev.add(DiffLine(DiffKind.del, a[x - 1], offset + x, 0));
          x--;
        }
      }
    }
    return rev.reversed.toList();
  }

  static ({int added, int removed}) stats(List<DiffLine> lines) {
    var add = 0;
    var del = 0;
    for (final l in lines) {
      if (l.kind == DiffKind.add) add++;
      if (l.kind == DiffKind.del) del++;
    }
    return (added: add, removed: del);
  }

  /// Keeps only changed lines with [context] lines around them. Gaps are
  /// represented by `null`.
  static List<DiffLine?> hunks(List<DiffLine> lines, {int context = 3}) {
    final keep = List<bool>.filled(lines.length, false);
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].kind != DiffKind.same) {
        for (var j = i - context; j <= i + context; j++) {
          if (j >= 0 && j < lines.length) keep[j] = true;
        }
      }
    }
    final out = <DiffLine?>[];
    var gap = false;
    for (var i = 0; i < lines.length; i++) {
      if (keep[i]) {
        out.add(lines[i]);
        gap = false;
      } else if (!gap) {
        out.add(null);
        gap = true;
      }
    }
    return out;
  }
}

class CodeAiParser {
  /// Returns the content of the longest fenced code block, or the trimmed
  /// reply when there is none.
  static String extractCode(String reply) {
    final re = RegExp(r'```[^\n`]*\n([\s\S]*?)```');
    String? best;
    for (final m in re.allMatches(reply)) {
      final body = m.group(1) ?? '';
      if (best == null || body.length > best.length) best = body;
    }
    if (best != null) {
      return best.endsWith('\n') ? best : '$best\n';
    }
    // Unterminated fence (model hit its token limit).
    final open = RegExp(r'```[^\n`]*\n([\s\S]*)$').firstMatch(reply);
    if (open != null) return open.group(1) ?? '';
    return reply.trim();
  }

  /// Short explanation written before the code block, if any.
  static String extractSummary(String reply) {
    final idx = reply.indexOf('```');
    final head = (idx < 0 ? '' : reply.substring(0, idx)).trim();
    return head.length > 600 ? '${head.substring(0, 600)}…' : head;
  }
}
