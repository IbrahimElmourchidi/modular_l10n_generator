import 'package:modular_l10n_generator/modular_l10n_generator.dart';
import 'package:test/test.dart';

void main() {
  group('parseIcu', () {
    test('plain text and placeholders', () {
      final result = parseIcu('Hello {name}!');
      expect(result.errors, isEmpty);
      expect(result.nodes, hasLength(3));
      expect((result.nodes[1] as IcuArgRef).name, 'name');
    });

    test('nested select inside a plural keeps # bound to the plural', () {
      final result = parseIcu(
        '{c, plural, other{{g, select, male{he has #} other{#}}}}',
      );
      expect(result.errors, isEmpty);
      final plural = result.nodes.single as IcuPlural;
      final select = plural.cases['other']!.single as IcuSelect;
      expect(select.cases['male']!.last, isA<IcuHash>());
    });

    test('offset and exact selectors', () {
      final plural =
          parseIcu('{n, plural, offset:1 =0{none} one{one} other{#}}')
              .nodes
              .single as IcuPlural;
      expect(plural.offset, 1);
      expect(plural.exactSelectors, ['=0']);
      expect(plural.cases.keys, ['=0', 'one', 'other']);
    });

    test('selectordinal is an ordinal plural', () {
      final plural = parseIcu('{n, selectordinal, one{#st} other{#th}}')
          .nodes
          .single as IcuPlural;
      expect(plural.ordinal, isTrue);
    });

    test("'' is a literal apostrophe, a quoted run is literal text", () {
      final nodes = parseIcu("It''s '{name}'").nodes;
      expect(nodes.single, isA<IcuText>());
      expect((nodes.single as IcuText).value, "It's {name}");
    });

    test('# outside a plural is text', () {
      final nodes = parseIcu('Order #{id}').nodes;
      expect((nodes.first as IcuText).value, 'Order #');
      expect((nodes.last as IcuArgRef).name, 'id');
    });

    test('an apostrophe that swallows a placeholder is reported', () {
      final result = parseIcu("Bienvenue à l'{place} aujourd'hui");
      expect(result.errors.single.message, contains('{place}'));
    });

    test('never throws on malformed input', () {
      for (final text in [
        '{',
        '}',
        '{a,',
        '{a, plural,',
        '{a, plural, one{x}',
        '{,}',
        "'{"
      ]) {
        expect(() => parseIcu(text), returnsNormally, reason: text);
        expect(parseIcu(text).errors, isNotEmpty, reason: text);
      }
    });

    test('unsupported types and bad categories are reported', () {
      expect(parseIcu('{d, date, short}').errors.single.message,
          contains('"date"'));
      expect(
        parseIcu('{n, plural, lots{x} other{y}}').errors.single.message,
        contains('"lots" is not a plural category'),
      );
      expect(
        parseIcu('{n, plural, =1{a} =1{b} other{c}}').errors.single.message,
        contains('Duplicate case "=1"'),
      );
    });
  });

  group('collectArgs', () {
    test('first-appearance order, recursing into case bodies', () {
      final args = collectArgs(
        parseIcu('{a} {n, plural, other{{g, select, x{{b}} other{}}}}').nodes,
      );
      expect(args.map((a) => a.name), ['a', 'n', 'g', 'b']);
    });

    test('the strictest role wins', () {
      final args =
          collectArgs(parseIcu('{count} {count, plural, other{#}}').nodes);
      expect(args.single.role, ArgRole.pluralOperand);
      expect(args.single.conflict, isNull);
    });

    test('two operand roles are a conflict', () {
      final args = collectArgs(
        parseIcu('{n, plural, other{{n, select, other{x}}}}').nodes,
      );
      expect(args.single.role, ArgRole.pluralOperand);
      expect(args.single.conflict, [ArgRole.selectOperand]);
    });
  });
}
