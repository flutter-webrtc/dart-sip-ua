import 'package:flutter/material.dart';

class NumPad extends StatefulWidget {
  final Function(String num) onPressed;
  NumPad({Key key, this.onPressed});
  @override
  _NumPadState createState() => _NumPadState();
}

class _NumPadState extends State<NumPad> {
  @override
  Widget build(BuildContext context) {
    var lables = [
      [
        {'1': ''},
        {'2': 'abc'},
        {'3': 'def'}
      ],
      [
        {'4': 'ghi'},
        {'5': 'jkl'},
        {'6': 'mno'}
      ],
      [
        {'7': 'pqrs'},
        {'8': 'tuv'},
        {'9': 'wxyz'}
      ],
      [
        {'*': ''},
        {'0': '+'},
        {'#': ''}
      ],
    ];
    return Container(
        width: 300,
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: lables
                .map((row) => Padding(
                    padding: const EdgeInsets.all(3),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: row
                            .map((label) => Container(
                                height: 72,
                                width: 72,
                                child: FlatButton(
                                  //heroTag: "num_$label",
                                  shape: CircleBorder(),
                                  child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: <Widget>[
                                        Text('${label.keys.first}',
                                            style: TextStyle(
                                                fontSize: 32,
                                                color: Theme.of(context)
                                                    .accentColor)),
                                        Text(
                                            '${label.values.first}'
                                                .toUpperCase(),
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Theme.of(context)
                                                    .disabledColor))
                                      ]),
                                  onPressed: () =>
                                      widget.onPressed(label.keys.first),
                                )))
                            .toList())))
                .toList()));
  }
}
