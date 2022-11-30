import 'package:flutter/material.dart';

class ActionButton extends StatefulWidget {
  final String? title;
  final String subTitle;
  final IconData? icon;
  final bool checked;
  final bool number;
  final Color? fillColor;
  final Function()? onPressed;
  final Function()? onLongPress;

  const ActionButton(
      {Key? key,
      this.title,
      this.subTitle = '',
      this.icon,
      this.onPressed,
      this.onLongPress,
      this.checked = false,
      this.number = false,
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
        GestureDetector(
            onLongPress: widget.onLongPress,
            onTap: widget.onPressed,
            child: RawMaterialButton(
              onPressed: widget.onPressed,
              splashColor: widget.fillColor ??
                  (widget.checked ? Colors.white : Colors.blue),
              fillColor: widget.fillColor ??
                  (widget.checked ? Colors.blue : Colors.white),
              elevation: 10.0,
              shape: CircleBorder(),
              child: Padding(
                padding: const EdgeInsets.all(15.0),
                child: widget.number
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                            Text('${widget.title}',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: widget.fillColor ?? Colors.grey[500],
                                )),
                            Text(widget.subTitle.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 8,
                                  color: widget.fillColor ?? Colors.grey[500],
                                ))
                          ])
                    : Icon(
                        widget.icon,
                        size: 30.0,
                        color: widget.fillColor != null
                            ? Colors.white
                            : (widget.checked ? Colors.white : Colors.blue),
                      ),
              ),
            )),
        widget.number
            ? Container(
                margin: EdgeInsets.symmetric(vertical: 4.0, horizontal: 2.0))
            : Container(
                margin: EdgeInsets.symmetric(vertical: 10.0, horizontal: 2.0),
                child: (widget.number || widget.title == null)
                    ? null
                    : Text(
                        widget.title!,
                        style: TextStyle(
                          fontSize: 15.0,
                          color: widget.fillColor ?? Colors.grey[500],
                        ),
                      ),
              )
      ],
    );
  }
}
