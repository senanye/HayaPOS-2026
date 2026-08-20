import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:hayapos_app/main.dart';
import 'package:hayapos_app/services/api_service.dart';
import 'package:hayapos_app/views/login_view.dart';

void main() {
  testWidgets('Login view renders successfully test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ApiService(),
        child: const MaterialApp(
          home: LoginView(),
        ),
      ),
    );

    // Verify that the login title exists
    expect(find.text('نظام هيا لنقاط البيع'), findsOneWidget);
    
    // Verify that username field exists
    expect(find.text('اسم المستخدم'), findsOneWidget);
    
    // Verify that password field exists
    expect(find.text('كلمة المرور'), findsOneWidget);

    // Verify that submit button exists
    expect(find.text('دخول النظام'), findsOneWidget);
  });
}
