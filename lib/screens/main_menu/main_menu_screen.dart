import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shirr/components/menu_item.dart';
import 'package:shirr/core/constants.dart';

class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  State<StatefulWidget> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  final TextStyle textStyleTitle = TextStyle(
    fontFamily: Constants.fontFamilyTitle,
    fontSize: Constants.fontSizeTitle,
    fontWeight: FontWeight.bold,
  );
  final TextStyle textStyleSubHead = TextStyle(
    fontFamily: Constants.fontFamilySubHead,
    fontSize: Constants.fontSizeSubHead,
    fontWeight: FontWeight.bold,
  );

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder:
              (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // App Name Title Text
                            Semantics(
                              label: Constants.appName,
                              image: true,
                              child: SvgPicture.asset(
                                'assets/branding/siir.svg',
                                width: 180,
                                height: 100,
                                colorFilter: ColorFilter.mode(
                                  Theme.of(context).colorScheme.onSurface,
                                  BlendMode.srcIn,
                                ),
                              ),
                            ),

                            Text("Main Menu", style: textStyleSubHead),
                            SizedBox(height: 20),
                            MenuItemDisk(
                              key: ValueKey("menu_aa"),
                              menuType: MenuType.audioAnalyzer,
                            ),
                            SizedBox(height: 16),
                            MenuItemDisk(
                              key: ValueKey("menu_ag"),
                              menuType: MenuType.audioGeneration,
                            ),
                            SizedBox(height: 16),
                            MenuItemDisk(
                              key: ValueKey("menu_av"),
                              menuType: MenuType.audioVisualization,
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 20),
                      Container(
                        padding: EdgeInsets.all(2.0),
                        alignment: Alignment.bottomCenter,
                        child: Text(
                          "v${Constants.version} ${Constants.copyrightText}",
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ),
      ),
    );
  }
}
