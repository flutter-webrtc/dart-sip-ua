import 'package:flutter/material.dart';

class ActionButton extends StatefulWidget {
  final String title;
  final IconData icon;
  final bool checked;
  final Color fillColor;
  final Function() onPressed;

  const ActionButton(
      {Key key,
      this.title,
      this.icon,
      this.onPressed,
      this.checked = false,
      this.fillColor})
      : super(key: key);

  @override
  _ActionButtonState createState() => _ActionButtonState();
}

class _ActionButtonState extends State<ActionButton> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        RawMaterialButton(
          onPressed: widget.onPressed,
          splashColor: widget.fillColor != null
              ? widget.fillColor
              : (widget.checked ? Colors.white : Colors.blue),
          fillColor: widget.fillColor != null
              ? widget.fillColor
              : (widget.checked ? Colors.blue : Colors.white),
          elevation: 10.0,
          shape: CircleBorder(),
          child: Padding(
            padding: const EdgeInsets.all(15.0),
            child: Icon(
              widget.icon,
              size: 30.0,
              color: widget.fillColor != null
                  ? Colors.white
                  : (widget.checked ? Colors.white : Colors.blue),
            ),
          ),
        ),
        Container(
          margin: EdgeInsets.symmetric(vertical: 10.0, horizontal: 2.0),
          child: Text(
            widget.title,
            style: TextStyle(
              fontSize: 15.0,
              color: widget.fillColor != null
                  ? widget.fillColor
                  : Colors.grey[500],
            ),
          ),
        )
      ],
    );
  }
}
