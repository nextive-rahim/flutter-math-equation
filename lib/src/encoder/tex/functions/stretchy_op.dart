part of '../functions.dart';

EncodeResult _stretchyOpEncoder(GreenNode node) {
  final arrowNode = node as StretchyOpNode;
  if (arrowNode.isCD) return _cdArrowEncoder(arrowNode);
  final command = arrowCommandMapping.entries
      .firstWhereOrNull((entry) => entry.value == arrowNode.symbol)
      ?.key;
  return command == null
      ? NonStrictEncodeResult(
          'unknown strechy_op',
          'No strict match for stretchy_op symbol under math mode: '
              '${unicodeLiteral(arrowNode.symbol)}',
        )
      : TexCommandEncodeResult(
          command: command,
          // The optional argument (below) comes first; this was the wrong
          // way round, so labels swapped sides on copy.
          args: <dynamic>[arrowNode.below, arrowNode.above],
        );
}
