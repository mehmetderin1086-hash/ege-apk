import 'dart:math' as math;

/// Pure-Dart recursive-descent mathematical expression evaluator.
class MathEvaluator {
  static double evaluate(String raw) {
    final normalized = raw
        .trim()
        .replaceAll('×', '*')
        .replaceAll('÷', '/')
        .replaceAll('−', '-')
        .replaceAll(',', '.')
        .replaceAll('√(', 'sqrt(')
        .replaceAll(' ', '');

    if (normalized.isEmpty) {
      throw const FormatException('Boş ifade.');
    }

    final parser = _Parser(normalized);
    final value = parser.parseExpression();
    if (!parser.isAtEnd) {
      throw const FormatException('Beklenmeyen karakter.');
    }
    if (!value.isFinite) {
      throw const FormatException('Tanımsız sayısal sonuç.');
    }
    return value;
  }

  static String formatResult(double value) {
    if (value == value.roundToDouble() && value.abs() < 1e15) {
      return value.toInt().toString();
    }
    final fixed = value.toStringAsFixed(8);
    return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
  }
}

class _Parser {
  final String input;
  int pos = 0;

  _Parser(this.input);

  bool get isAtEnd => pos >= input.length;

  String get current => input[pos];

  double parseExpression() {
    var left = parseTerm();
    while (!isAtEnd && (current == '+' || current == '-')) {
      final op = current;
      pos++;
      final right = parseTerm();
      left = op == '+' ? left + right : left - right;
    }
    return left;
  }

  double parseTerm() {
    var left = parsePower();
    while (!isAtEnd && (current == '*' || current == '/' || current == '%')) {
      final op = current;
      pos++;
      final right = parsePower();
      if (op == '*') {
        left *= right;
      } else if (op == '/') {
        if (right == 0) throw const FormatException('Sıfıra bölünemez.');
        left /= right;
      } else {
        if (right == 0) throw const FormatException('Sıfıra bölünemez.');
        left %= right;
      }
    }
    return left;
  }

  double parsePower() {
    final base = parseUnary();
    if (!isAtEnd && current == '^') {
      pos++;
      final exp = parsePower();
      return math.pow(base, exp).toDouble();
    }
    return base;
  }

  double parseUnary() {
    if (!isAtEnd && current == '-') {
      pos++;
      return -parseUnary();
    }
    if (!isAtEnd && current == '+') {
      pos++;
      return parseUnary();
    }
    return parsePrimary();
  }

  double parsePrimary() {
    if (isAtEnd) throw const FormatException('Eksik ifade.');

    if (current == '(') {
      pos++;
      final inner = parseExpression();
      if (isAtEnd || current != ')') {
        throw const FormatException('Kapanmayan parantez.');
      }
      pos++;
      return inner;
    }

    if (_isLetter(current)) {
      final start = pos;
      while (!isAtEnd && (_isLetter(current) || _isDigit(current))) {
        pos++;
      }
      final ident = input.substring(start, pos).toLowerCase();
      if (ident == 'pi') return math.pi;
      if (ident == 'e') return math.e;

      if (isAtEnd || current != '(') {
        throw FormatException('Bilinmeyen ifade: $ident');
      }
      pos++; // skip '('
      final arg = parseExpression();
      if (isAtEnd || current != ')') {
        throw const FormatException('Fonksiyon parantezi kapanmadı.');
      }
      pos++;

      switch (ident) {
        case 'sqrt':
        case 'karekök':
          if (arg < 0) throw const FormatException('Negatif sayının karekökü yok.');
          return math.sqrt(arg);
        case 'sin':
          return math.sin(arg);
        case 'cos':
          return math.cos(arg);
        case 'tan':
          return math.tan(arg);
        case 'abs':
          return arg.abs();
        case 'ln':
          if (arg <= 0) throw const FormatException('Logaritma 0 veya negatif olamaz.');
          return math.log(arg);
        case 'log':
          if (arg <= 0) throw const FormatException('Logaritma 0 veya negatif olamaz.');
          return math.log(arg) / math.ln10;
        default:
          throw FormatException('Desteklenmeyen fonksiyon: $ident');
      }
    }

    final numStart = pos;
    var hasDot = false;
    while (!isAtEnd && (_isDigit(current) || (current == '.' && !hasDot))) {
      if (current == '.') hasDot = true;
      pos++;
    }
    if (pos == numStart) {
      throw FormatException('Geçersiz karakter: $current');
    }
    return double.parse(input.substring(numStart, pos));
  }

  bool _isDigit(String c) => c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;
  bool _isLetter(String c) {
    final code = c.codeUnitAt(0);
    return (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
  }
}
