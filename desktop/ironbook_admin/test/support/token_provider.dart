import 'package:ironbook_auth/ironbook_auth.dart';

class FakeAccessTokenProvider implements AccessTokenProvider {
  FakeAccessTokenProvider([this.token = 'fixture-access-token']);

  String? token;
  int reads = 0;
  @override
  Future<String?> getAccessToken() async {
    reads++;
    return token;
  }
}
