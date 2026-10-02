import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:shirr/core/constants.dart';
import 'package:shirr/services/snapshot_handler.dart';

void showPlotSelectorDialog(BuildContext context, PageController pageController) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final plotOptions = ["Amplitude, Time", "Fast Fourier Transform", "Phase, Frequency and Amplitude ", "Relative Loudness", "MFCC Heatmap", "Spectral Centroid", "Spectral Roll-Off Freq.", "Spectral Flatness", "Notes Histogram"];

  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        backgroundColor: isDark ? const Color(0xFF202020) : const Color(0xFF000000),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20)
        ),
        title: Text(
          "Choose Plot",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: Constants.fontFamilySubHead,
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: isDark ? const Color(0xFFD5D5D5) : const Color(0xFFFFFFFF),
          ),
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 320,
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            children: List.generate(plotOptions.length, (index) {
              return ElevatedButton(
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.pressed)) {
                      return isDark ? const Color(0xFF1E1E1E) : const Color(0xFF1E1E1E);
                    }
                    return isDark ? const Color(0xFF303030) : const Color(0xFF303030);
                  }),
                  foregroundColor: WidgetStateProperty.all(Colors.white),
                  padding: WidgetStateProperty.all(
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  shape: WidgetStateProperty.all(
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                  pageController.animateToPage(
                    index,
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeInOut,
                  );
                },
                child: Text(
                  textAlign: TextAlign.center,
                  plotOptions[index],
                  style: TextStyle(
                    fontFamily: Constants.fontFamilyBody,
                    fontWeight: FontWeight.bold,
                    fontSize: 16),
                ),
              );
            }),
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: isDark ? const Color(0xFFD5D5D5) : const Color(0xFFFFFFFF),
            ),
            child: Text("Cancel", style: TextStyle(fontFamily: Constants.fontFamilyBody),),
          ),
        ],
      );
    },
  );
}


void onSavePress(BuildContext context, GlobalKey repaintKey) async {

    bool isDark = Theme.of(context).brightness == Brightness.dark;

    final pngBytes = await captureSnapshot(repaintKey);
    if (pngBytes == null) return;
    if (!context.mounted) return;
    bool? shouldSave = await showDialog<bool>(
  context: context,
  builder: (_) => AlertDialog(
    backgroundColor: isDark ? const Color(0xFF202020) : const Color(0xFF000000),
    title: Text(
      "Snapshot",
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: isDark ? const Color(0xFFD5D5D5) : const Color(0xFFFFFFFF),
      ),
    ),
      content: Image.memory(pngBytes),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          style: TextButton.styleFrom(
            foregroundColor: isDark ? Color(0xFFD5D5D5) :  Color(0xFFFFFFFF),
          ),
          child: const Text("Cancel"),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.pressed)) {
                return isDark? Color(0xFF1E1E1E) : Color(0xFF1E1E1E);
              }
              return isDark? Color(0xFF303030) : Color(0xFF303030);
            }),
            foregroundColor: WidgetStateProperty.all(Colors.white),
            padding: WidgetStateProperty.all(
              const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
          child: const Text("Save"),
        ),
      ],
    ),
  );


    if (shouldSave == true) {
      final result = await saveSnapshotToStorage(pngBytes);
      if (result.$1) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Snapshot saved at ${result.$2}')),
        );
        return;
      } else {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('OOPS, there is a bug')),
    );
      }
    } 
  }


void onPressHelp(BuildContext context) {

  final isDark = Theme.of(context).brightness == Brightness.dark;
  Color textColor = isDark? Color(0xFFFFFFFF): Color(0xFFFFFFFF);
  Color bgColor = isDark ? const Color(0xFF303030) : const Color(0xFF1E1E1E);

  final textStyle = TextStyle(
    fontFamily: Constants.fontFamilyBody,
    color: textColor,
    fontSize: 16,
  );

  showDialog(context: context, builder: 
    (context) {
      return SizedBox(
        height: 10,
        child: SimpleDialog(
          contentPadding: EdgeInsets.all(16),
          title: Text(
            "User Manual",
            style: TextStyle(
              fontFamily: Constants.fontFamilyTitle,
              fontSize: Constants.fontSizeSubHead,
              fontWeight: FontWeight.bold,
              color: isDark? Color(0xFFFFFFFF): Color(0xFFD5D5D5),
            ),
            textAlign: TextAlign.center,
          ),
          backgroundColor: bgColor,
          elevation: 10,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)
          ),
          insetPadding: EdgeInsets.all(16),
          children: [
            Padding(
                  padding: EdgeInsets.all(10),
                  child: Text(
                    "Controls Guide",
                    style: TextStyle(
                      fontFamily: Constants.fontFamilySubHead,
                      fontWeight: FontWeight.bold,
                      fontSize: Constants.fontSizeSubHead,
                      color: textColor
                      ),
                    textAlign: TextAlign.center,
                  ),
                ),
            Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                "Audio Analyzer Menu provides with many tools and visualization of the audio signals. It is a handy application to see sounds in astounding forms.",
                style: textStyle,
                textAlign: TextAlign.center,
              ),
            ),
            // Section 1.1
            Center(
              child: Column(
                spacing: 8,
                children: [
                  SvgPicture.asset(Constants.pathIconPlayLight),
                  Padding(
                    padding: EdgeInsets.all(10),
                    child: Text(
                      "Play Button is used to control the audio stream, weather from a file or your microphone",
                      style: textStyle,
                      textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
            // Section 1.2
            Center(
              child: Column(
                spacing: 8,
                children: [
                  SvgPicture.asset(Constants.pathIconBtnSave),
                  Padding(
                    padding: EdgeInsets.all(10),
                    child: Text(
                      "This is Snapshot Capture, it helps export the Snapshots in .png format.",
                      style: textStyle,
                      textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
            Center(
              child: Column(
                spacing: 8,
                children: [
                  SvgPicture.asset(Constants.pathIconBtnFocus),
                  Padding(
                    padding: EdgeInsets.all(10),
                    child: Text(
                      "In Focus mode, user cannot swipe in between different slides.",
                      style: textStyle,
                      textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),Center(
              child: Column(
                spacing: 8,
                children: [
                  SvgPicture.asset(Constants.pathIconBtnMic),
                  Padding(
                    padding: EdgeInsets.all(10),
                    child: Text(
                      "Since there are two modes of getting streams in sIIr, i.e., Microphone and Audio File. Pressing `Mic` sets the stream to microphone.",
                      style: textStyle,
                      textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
            Center(
              child: Column(
                spacing: 8,
                children: [
                  SvgPicture.asset(Constants.pathIconBtnDisk),
                  Padding(
                    padding: EdgeInsets.all(10),
                    child: Text(
                      "It toggles the stream input to the file. The file is chosen by the user locally from the device.",
                      style: textStyle,
                      textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
            Center(
              child: Column(
                spacing: 8,
                children: [
                  SvgPicture.asset(Constants.pathIconBtnOptions),
                  Padding(
                    padding: EdgeInsets.all(10),
                    child: Text(
                      "From the list of Plots, the `Choose Plot` or `Options` button helps quickly navigate to required plot.",
                      style: textStyle,
                      textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
            Center(
              child: Column(
                spacing: 8,
                children: [
                  SvgPicture.asset(Constants.pathIconBtnInteract),
                  Padding(
                    padding: EdgeInsets.all(10),
                    child: Text(
                      "`Interactive` mode disables graph scaling and movement and fixes a window of the graph and enables point-wise viewing of data.",
                      style: textStyle,
                      textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),

            // Final Note
            Column(
              children: [
                Padding(
                  padding: EdgeInsets.all(10),
                  child: Text(
                    "Plot Interaction Guide",
                    style: TextStyle(
                      fontFamily: Constants.fontFamilySubHead,
                      fontWeight: FontWeight.bold,
                      fontSize: Constants.fontSizeSubHead,
                      color: textColor
                      ),
                    textAlign: TextAlign.center,
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(10),
                  child: Text(
                    "User can switch between plots by vertical swipes. Plot interaction like `zooming` and `dragging` is fully allowed in non-interactive mode. In `Interactive` mode, user can see point-wise labels of each data point by touching it.",
                    style: textStyle,
                    textAlign: TextAlign.center,
                  ),
                ),
                SizedBox(height: 20,),

                ElevatedButton(
                  style: ButtonStyle(
                    backgroundColor: WidgetStatePropertyAll(Colors.white),
                    foregroundColor: WidgetStatePropertyAll(Colors.black),
                    surfaceTintColor: WidgetStatePropertyAll(Colors.grey.shade800),
                  ),
                  onPressed: () {}, 
                  child: Text("Report Bugs")
                ),
                Padding(
                    padding: EdgeInsets.all(10),
                    child: Text(
                      "v${Constants.version} ${Constants.copyrightText}\nhavoksahil@github.com",
                      style: textStyle,
                      textAlign: TextAlign.center,
                    ),
                ),
              ],
            ),
          ],
        ),
      );
    }
  );
}