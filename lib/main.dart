import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

Color wh(double o) => Color.fromRGBO(255, 255, 255, o);
Color bk(double o) => Color.fromRGBO(0, 0, 0, o);

const S = {
  'now': ['Now', 'اکنون'], 'today': ['Today', 'امروز'],
  'feels': ['Feels like', 'حس واقعی'], 'hum': ['Humidity', 'رطوبت'],
  'wind': ['Wind', 'باد'], 'pres': ['Pressure', 'فشار'], 'uv': ['UV index', 'شاخص UV'],
  'rain': ['Precipitation', 'بارش'], 'rise': ['Sunrise', 'طلوع'], 'set': ['Sunset', 'غروب'],
  'hr': ['Hourly forecast', 'پیش‌بینی ساعتی'], 'dy': ['7-day forecast', 'پیش‌بینی ۷ روزه'],
  'retry': ['Retry', 'تلاش دوباره'],
  'err': ['Couldn’t load weather. Check your connection.', 'دریافت اطلاعات ممکن نشد. اینترنت را بررسی کنید.'],
  'me': ['My location', 'موقعیت من'], 'srch': ['Search city…', 'جستجوی شهر…'],
  'gps': ['Use my location', 'استفاده از موقعیت من'], 'saved': ['Saved cities', 'شهرهای ذخیره‌شده'],
};
const WT = [
  ['Clear', 'آسمان صاف'], ['Partly cloudy', 'کمی ابری'], ['Overcast', 'ابری'], ['Fog', 'مه‌آلود'],
  ['Drizzle', 'نم‌نم باران'], ['Rain', 'بارانی'], ['Snow', 'برفی'], ['Thunderstorm', 'رعد و برق'],
];
const FW = ['دوشنبه', 'سه‌شنبه', 'چهارشنبه', 'پنجشنبه', 'جمعه', 'شنبه', 'یکشنبه'];
const JM = ['فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور', 'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند'];
const EW = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const EM = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

List<int> jal(int gy, int gm, int gd) {
  const g = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334];
  final gy2 = gm > 2 ? gy + 1 : gy;
  var days = 355666 + (365 * gy) + ((gy2 + 3) ~/ 4) - ((gy2 + 99) ~/ 100) + ((gy2 + 399) ~/ 400) + gd + g[gm - 1];
  var jy = -1595 + (33 * (days ~/ 12053));
  days %= 12053;
  jy += 4 * (days ~/ 1461);
  days %= 1461;
  if (days > 365) { jy += (days - 1) ~/ 365; days = (days - 1) % 365; }
  final jm = days < 186 ? 1 + days ~/ 31 : 7 + (days - 186) ~/ 30;
  final jd = 1 + (days < 186 ? days % 31 : (days - 186) % 30);
  return [jy, jm, jd];
}

(IconData, int) wi(int c, bool day) {
  if (c == 0) return (day ? Icons.wb_sunny_rounded : Icons.nightlight_round, 0);
  if (c == 1 || c == 2) return (day ? Icons.wb_cloudy_rounded : Icons.nights_stay_rounded, 1);
  if (c == 3) return (Icons.cloud_rounded, 2);
  if (c == 45 || c == 48) return (Icons.blur_on_rounded, 3);
  if (c >= 51 && c <= 57) return (Icons.grain_rounded, 4);
  if ((c >= 61 && c <= 67) || (c >= 80 && c <= 82)) return (Icons.water_drop_rounded, 5);
  if ((c >= 71 && c <= 77) || c == 85 || c == 86) return (Icons.ac_unit_rounded, 6);
  return (Icons.thunderstorm_rounded, 7);
}

List<Color> bgc(bool day, int k) {
  final cl = k >= 2;
  if (day) return cl ? [const Color(0xFF6B7F95), const Color(0xFFA9B8C6)] : [const Color(0xFF2E8BEA), const Color(0xFF8FD0FF)];
  return cl ? [const Color(0xFF151B33), const Color(0xFF39425F)] : [const Color(0xFF070D26), const Color(0xFF1E2B5E)];
}

class City {
  final String name;
  final double lat, lon;
  City(this.name, this.lat, this.lon);
  Map toJson() => {'n': name, 'a': lat, 'o': lon};
  factory City.fromJson(Map j) => City(j['n'], (j['a'] as num).toDouble(), (j['o'] as num).toDouble());
}

class Store extends ChangeNotifier {
  bool fa = true, f = false, loading = true, err = false;
  List<City> cities = [City('Istanbul', 41.0082, 28.9784)];
  int idx = 0, _req = 0;
  Map? d;
  late SharedPreferences p;
  City get city => cities[idx];

  String t(String k) => S[k]![fa ? 1 : 0];
  String dg(String s) => fa ? s.replaceAllMapped(RegExp(r'\d'), (x) => '۰۱۲۳۴۵۶۷۸۹'[int.parse(x[0]!)]) : s;
  String tp(num c) => dg('${(f ? c * 9 / 5 + 32 : c).round()}°');
  String nm(City c) => c.name == '@' ? t('me') : c.name;
  String wd(DateTime d) => fa ? FW[d.weekday - 1] : EW[d.weekday - 1];
  String ds(DateTime d) {
    if (fa) { final j = jal(d.year, d.month, d.day); return dg('${wd(d)} ${j[2]} ${JM[j[1] - 1]}'); }
    return '${wd(d)}, ${EM[d.month - 1]} ${d.day}';
  }

  Future<void> init() async {
    p = await SharedPreferences.getInstance();
    fa = p.getBool('fa') ?? true;
    f = p.getBool('f') ?? false;
    final c = p.getStringList('c');
    if (c != null && c.isNotEmpty) {
      cities = c.map((e) => City.fromJson(jsonDecode(e))).toList();
      idx = math.min(p.getInt('i') ?? 0, cities.length - 1);
    } else {
      final g = await locate();
      if (g != null) { cities = [g]; idx = 0; save(); }
    }
    await load();
  }

  Future<City?> locate() async {
    try {
      var pm = await Geolocator.checkPermission();
      if (pm == LocationPermission.denied) pm = await Geolocator.requestPermission();
      if (pm == LocationPermission.denied || pm == LocationPermission.deniedForever) return null;
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 12)));
      return City('@', pos.latitude, pos.longitude);
    } catch (_) { return null; }
  }

  void save() {
    p.setBool('fa', fa);
    p.setBool('f', f);
    p.setInt('i', idx);
    p.setStringList('c', cities.map((e) => jsonEncode(e.toJson())).toList());
  }

  Future<void> load() async {
    final id = ++_req;
    loading = true; err = false; notifyListeners();
    try {
      final u = Uri.parse('https://api.open-meteo.com/v1/forecast?latitude=${city.lat}&longitude=${city.lon}'
          '&current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,pressure_msl,wind_speed_10m,wind_direction_10m'
          '&hourly=temperature_2m,weather_code,precipitation_probability,is_day'
          '&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,uv_index_max,precipitation_sum,precipitation_probability_max'
          '&timezone=auto&forecast_days=7');
      final r = await http.get(u).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) throw 'http';
      if (id != _req) return;
      d = jsonDecode(r.body) as Map;
    } catch (_) {
      if (id != _req) return;
      err = true;
    }
    loading = false; notifyListeners();
  }

  void sel(int i) { idx = i; save(); d = null; load(); }
  void add(City c) {
    if (c.name == '@') cities.removeWhere((e) => e.name == '@');
    cities.add(c); idx = cities.length - 1; save(); d = null; load();
  }
  void remove(int i) {
    if (cities.length < 2) return;
    final cur = city;
    cities.removeAt(i);
    final j = cities.indexOf(cur);
    if (j < 0) { idx = 0; save(); d = null; load(); } else { idx = j; save(); notifyListeners(); }
  }
  void toggleLang() { fa = !fa; save(); notifyListeners(); }
  void toggleUnit() { f = !f; save(); notifyListeners(); }
}

final st = Store();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent));
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: st,
      builder: (_, __) => MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'Skycast',
            theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
            builder: (c, w) => Directionality(textDirection: st.fa ? TextDirection.rtl : TextDirection.ltr, child: w!),
            home: const Home(),
          ));
}

class Glass extends StatelessWidget {
  final Widget child;
  final EdgeInsets pad;
  final double r;
  final bool dark;
  const Glass({super.key, required this.child, this.pad = const EdgeInsets.all(16), this.r = 28, this.dark = false});
  @override
  Widget build(BuildContext c) => ClipRRect(
      borderRadius: BorderRadius.circular(r),
      child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
          child: Container(
              padding: pad,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(r),
                gradient: LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: dark ? [bk(.45), bk(.3)] : [wh(.3), wh(.08)]),
                border: Border.all(color: wh(.4), width: 1),
              ),
              child: child)));
}

Widget pill(String s, VoidCallback f) => GestureDetector(
    onTap: f,
    child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(color: wh(.2), borderRadius: BorderRadius.circular(20), border: Border.all(color: wh(.3))),
        child: Text(s, style: const TextStyle(fontWeight: FontWeight.w600))));

class Sky extends CustomPainter {
  final ValueNotifier<double> t;
  final bool day;
  final int k;
  Sky(this.t, this.day, this.k) : super(repaint: t);

  @override
  void paint(Canvas c, Size s) {
    final T = t.value;
    final pos = Offset(s.width * .78, s.height * .15 + 5 * math.sin(T * .6));
    final dim = k >= 3 ? .35 : 1.0;
    if (!day) {
      final r = math.Random(7);
      for (var i = 0; i < 60; i++) {
        final x = r.nextDouble() * s.width, y = r.nextDouble() * s.height * .7, z = .5 + r.nextDouble();
        c.drawCircle(Offset(x, y), z, Paint()..color = wh((.25 + .6 * (.5 + .5 * math.sin(T * 1.2 + i))) * (k >= 2 ? .35 : 1)));
      }
    }
    if (k < 4) {
      final gc = day ? const [255, 236, 150] : const [180, 200, 255];
      c.drawCircle(pos, 90, Paint()..shader = RadialGradient(colors: [
        Color.fromRGBO(gc[0], gc[1], gc[2], .5 * dim), Color.fromRGBO(gc[0], gc[1], gc[2], 0)
      ]).createShader(Rect.fromCircle(center: pos, radius: 90)));
      if (day) {
        final rp = Paint()..color = Color.fromRGBO(255, 240, 180, .5 * dim)..strokeWidth = 3..strokeCap = StrokeCap.round;
        for (var i = 0; i < 12; i++) {
          final a = i * math.pi / 6 + T * .15, u = Offset(math.cos(a), math.sin(a));
          c.drawLine(pos + u * 46, pos + u * (58 + 6 * math.sin(T * 2 + i)), rp);
        }
        c.drawCircle(pos, 30, Paint()..color = Color.fromRGBO(255, 244, 200, dim));
      } else {
        final full = Path()..addOval(Rect.fromCircle(center: pos, radius: 30));
        final cut = Path()..addOval(Rect.fromCircle(center: pos + const Offset(14, -8), radius: 26));
        c.drawPath(Path.combine(PathOperation.difference, full, cut), Paint()..color = Color.fromRGBO(240, 244, 255, dim));
      }
    }
    final n = k >= 2 ? 7 : 4;
    for (var i = 0; i < n; i++) {
      final w = 150.0 + (i * 53) % 90;
      final x = (T * (5 + i * 2.5) + i * 190) % (s.width + 2 * w) - w;
      final y = s.height * (.08 + .09 * i) + 8 * math.sin(T * .3 + i);
      final o = day ? (k >= 2 ? .5 : .28) : (k >= 2 ? .22 : .1);
      c.saveLayer(null, Paint()..color = wh(o));
      final p = Paint()..color = Colors.white;
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x, y), width: w, height: w * .28), Radius.circular(w * .14)), p);
      c.drawCircle(Offset(x - w * .12, y - w * .1), w * .15, p);
      c.drawCircle(Offset(x + w * .1, y - w * .14), w * .19, p);
      c.restore();
    }
    if (k == 4 || k == 5 || k == 7) {
      final p = Paint()..color = wh(.35)..strokeWidth = 1.4;
      for (var i = 0; i < 70; i++) {
        final x = (i * 53.0) % s.width, y = (T * 520 + i * 97.0) % s.height;
        c.drawLine(Offset(x, y), Offset(x - 3, y + 14), p);
      }
    }
    if (k == 6) {
      final p = Paint()..color = wh(.8);
      for (var i = 0; i < 60; i++) {
        final x = ((i * 53.0) + 20 * math.sin(T + i)) % s.width, y = (T * 60 + i * 97.0) % s.height;
        c.drawCircle(Offset(x, y), 2, p);
      }
    }
  }

  @override
  bool shouldRepaint(Sky o) => o.day != day || o.k != k;
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with SingleTickerProviderStateMixin {
  final time = ValueNotifier<double>(0);
  late final Ticker tk;

  @override
  void initState() {
    super.initState();
    tk = createTicker((d) => time.value = d.inMicroseconds / 1e6)..start();
    st.init();
  }

  @override
  void dispose() { tk.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: st,
      builder: (_, __) {
        final d = st.d;
        final day = d == null || d['current']['is_day'] == 1;
        final k = d == null ? 0 : wi(d['current']['weather_code'], day).$2;
        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(children: [
            Positioned.fill(
                child: AnimatedContainer(
                    duration: const Duration(seconds: 1),
                    decoration: BoxDecoration(
                        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: bgc(day, k))))),
            Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: Sky(time, day, k)))),
            SafeArea(child: Column(children: [header(context), Expanded(child: body(context, d))])),
          ]),
        );
      });

  Widget header(BuildContext c) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Glass(
          r: 24,
          pad: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(children: [
            Expanded(
                child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => showModalBottomSheet(
                        context: c, isScrollControlled: true, backgroundColor: Colors.transparent,
                        barrierColor: bk(.3), builder: (_) => const CitySheet()),
                    child: Row(children: [
                      const Icon(Icons.location_on_rounded, size: 18),
                      const SizedBox(width: 6),
                      Flexible(child: Text(st.nm(st.city), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
                      const Icon(Icons.keyboard_arrow_down_rounded),
                    ]))),
            pill(st.f ? '°F' : '°C', st.toggleUnit),
            const SizedBox(width: 6),
            pill(st.fa ? 'EN' : 'فا', st.toggleLang),
          ])));

  Widget ttl(IconData i, String k) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        Icon(i, size: 15, color: wh(.7)),
        const SizedBox(width: 6),
        Text(st.t(k), style: TextStyle(fontSize: 13, color: wh(.75), fontWeight: FontWeight.w600)),
      ]));

  Widget val(String v, [String? u]) => Text.rich(TextSpan(text: v, children: [
        if (u != null) TextSpan(text: ' $u', style: TextStyle(fontSize: 12, color: wh(.7))),
      ]));

  Widget tile(double w, IconData i, String k, Widget v) => SizedBox(
      width: w,
      child: Glass(
          r: 24,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(i, size: 16, color: wh(.75)),
              const SizedBox(width: 6),
              Text(st.t(k), style: TextStyle(fontSize: 13, color: wh(.75))),
            ]),
            const SizedBox(height: 10),
            DefaultTextStyle(style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w500, color: Colors.white), child: v),
          ])));

  Widget drow(Map dl, int i, num lo, num hi) {
    final dt = DateTime.parse(dl['time'][i]);
    final double a = ((dl['temperature_2m_min'][i] - lo) / math.max(1, hi - lo)).toDouble();
    final double b = ((dl['temperature_2m_max'][i] - lo) / math.max(1, hi - lo)).toDouble();
    final int pr = (dl['precipitation_probability_max'][i] ?? 0).round();
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Row(children: [
          SizedBox(width: 66, child: Text(i == 0 ? st.t('today') : st.wd(dt), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500))),
          Icon(wi(dl['weather_code'][i], true).$1, size: 22),
          SizedBox(width: 40, child: Text(pr >= 20 ? st.dg('$pr%') : '', textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Color(0xFF9EDBFF)))),
          SizedBox(width: 36, child: Text(st.tp(dl['temperature_2m_min'][i]), textAlign: TextAlign.center, style: TextStyle(color: wh(.75)))),
          Expanded(
              child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: LayoutBuilder(builder: (_, bc) {
                    final w = bc.maxWidth;
                    return SizedBox(
                        height: 5,
                        child: Stack(children: [
                          Container(decoration: BoxDecoration(color: wh(.2), borderRadius: BorderRadius.circular(3))),
                          PositionedDirectional(
                              start: w * a, width: math.max(6.0, w * (b - a)), top: 0, bottom: 0,
                              child: Container(decoration: BoxDecoration(
                                  gradient: const LinearGradient(colors: [Color(0xFF7DD3FC), Color(0xFFFCD34D)]),
                                  borderRadius: BorderRadius.circular(3)))),
                        ]));
                  }))),
          SizedBox(width: 36, child: Text(st.tp(dl['temperature_2m_max'][i]), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]));
  }

  Widget body(BuildContext c, Map? d) {
    if (d == null) {
      return Center(
          child: st.loading
              ? const CircularProgressIndicator(color: Colors.white)
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Glass(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(st.t('err'), textAlign: TextAlign.center),
                    const SizedBox(height: 14),
                    pill(st.t('retry'), st.load),
                  ]))));
    }
    final cur = d['current'], hr = d['hourly'], dl = d['daily'];
    final day = cur['is_day'] == 1;
    final info = wi(cur['weather_code'], day);
    final now = DateTime.parse(cur['time']);
    final ht = hr['time'] as List;
    final cp = (cur['time'] as String).substring(0, 13);
    var s0 = ht.indexWhere((e) => (e as String).compareTo(cp) >= 0);
    if (s0 < 0) s0 = 0;
    final cnt = math.min(24, ht.length - s0);
    final mn = (dl['temperature_2m_min'] as List).cast<num>(), mx = (dl['temperature_2m_max'] as List).cast<num>();
    final lo = mn.reduce((a, b) => math.min(a, b)), hi = mx.reduce((a, b) => math.max(a, b));
    final tw = (MediaQuery.of(c).size.width - 32 - 12) / 2;
    const gap = SizedBox(height: 12);

    return RefreshIndicator(
        onRefresh: st.load,
        child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Column(children: [
                Text(st.ds(now), style: TextStyle(color: wh(.85), fontSize: 14)),
                const SizedBox(height: 14),
                Icon(info.$1, size: 60),
                Text(st.tp(cur['temperature_2m']), style: const TextStyle(fontSize: 104, fontWeight: FontWeight.w200, height: 1.05)),
                Text(WT[info.$2][st.fa ? 1 : 0], style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                Text('↑ ${st.tp(mx[0])}    ↓ ${st.tp(mn[0])}', style: TextStyle(fontSize: 16, color: wh(.85))),
              ]),
              const SizedBox(height: 28),
              Glass(
                  pad: const EdgeInsets.symmetric(vertical: 14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    ttl(Icons.schedule_rounded, 'hr'),
                    const SizedBox(height: 8),
                    SizedBox(
                        height: 108,
                        child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            itemCount: cnt,
                            itemBuilder: (_, i) {
                              final j = s0 + i;
                              final pr = (hr['precipitation_probability'][j] ?? 0).round();
                              return SizedBox(
                                  width: 60,
                                  child: Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                                    Text(i == 0 ? st.t('now') : st.dg((ht[j] as String).substring(11, 16)), style: TextStyle(fontSize: 12, color: wh(.8))),
                                    Icon(wi(hr['weather_code'][j], hr['is_day'][j] == 1).$1, size: 24),
                                    Text(st.tp(hr['temperature_2m'][j]), style: const TextStyle(fontWeight: FontWeight.w600)),
                                    Text(pr >= 20 ? st.dg('$pr%') : ' ', style: const TextStyle(fontSize: 11, color: Color(0xFF9EDBFF))),
                                  ]));
                            })),
                  ])),
              gap,
              Glass(
                  pad: const EdgeInsets.symmetric(vertical: 14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    ttl(Icons.calendar_month_rounded, 'dy'),
                    const SizedBox(height: 6),
                    for (var i = 0; i < (dl['time'] as List).length; i++) drow(dl, i, lo, hi),
                  ])),
              gap,
              Wrap(spacing: 12, runSpacing: 12, children: [
                tile(tw, Icons.thermostat_rounded, 'feels', val(st.tp(cur['apparent_temperature']))),
                tile(tw, Icons.water_drop_outlined, 'hum', val(st.dg('${cur['relative_humidity_2m'].round()}%'))),
                tile(tw, Icons.air_rounded, 'wind', Row(mainAxisSize: MainAxisSize.min, children: [
                  val(st.dg('${cur['wind_speed_10m'].round()}'), 'km/h'),
                  const SizedBox(width: 6),
                  Transform.rotate(angle: (cur['wind_direction_10m'] + 180) * math.pi / 180, child: const Icon(Icons.navigation_rounded, size: 18)),
                ])),
                tile(tw, Icons.speed_rounded, 'pres', val(st.dg('${cur['pressure_msl'].round()}'), 'hPa')),
                tile(tw, Icons.wb_sunny_outlined, 'uv', val(st.dg('${(dl['uv_index_max'][0] ?? 0).round()}'))),
                tile(tw, Icons.umbrella_rounded, 'rain', val(st.dg((dl['precipitation_sum'][0] ?? 0).toStringAsFixed(1)), 'mm')),
                tile(tw, Icons.wb_twilight_rounded, 'rise', val(st.dg((dl['sunrise'][0] as String).substring(11, 16)))),
                tile(tw, Icons.nights_stay_outlined, 'set', val(st.dg((dl['sunset'][0] as String).substring(11, 16)))),
              ]),
              const SizedBox(height: 20),
              Center(child: Text('Open-Meteo.com', style: TextStyle(fontSize: 11, color: wh(.5)))),
            ]));
  }
}

class CitySheet extends StatefulWidget {
  const CitySheet({super.key});
  @override
  State<CitySheet> createState() => _CS();
}

class _CS extends State<CitySheet> {
  List res = [];
  String q = '';

  Future<void> search(String s) async {
    q = s;
    if (s.trim().length < 2) { setState(() => res = []); return; }
    try {
      final r = await http.get(Uri.parse(
          'https://geocoding-api.open-meteo.com/v1/search?name=${Uri.encodeComponent(s.trim())}&count=8&language=${st.fa ? 'fa' : 'en'}'));
      if (q != s || !mounted) return;
      setState(() => res = (jsonDecode(r.body)['results'] ?? []) as List);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext c) => ListenableBuilder(
      listenable: st,
      builder: (_, __) => Padding(
          padding: EdgeInsets.fromLTRB(12, 0, 12, 12 + MediaQuery.of(c).viewInsets.bottom),
          child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * .75),
              child: Glass(
                  dark: true,
                  pad: const EdgeInsets.all(14),
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    TextField(
                        onChanged: search,
                        decoration: InputDecoration(
                            hintText: st.t('srch'),
                            prefixIcon: const Icon(Icons.search_rounded),
                            filled: true,
                            fillColor: wh(.12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none))),
                    const SizedBox(height: 6),
                    ListTile(
                        leading: const Icon(Icons.my_location_rounded),
                        title: Text(st.t('gps')),
                        onTap: () async {
                          final g = await st.locate();
                          if (g != null) { st.add(g); if (mounted) Navigator.pop(context); }
                        }),
                    Flexible(
                        child: ListView(shrinkWrap: true, children: q.trim().length >= 2
                            ? [
                                for (final r in res)
                                  ListTile(
                                      leading: const Icon(Icons.add_location_alt_outlined),
                                      title: Text('${r['name']}'),
                                      subtitle: Text([r['admin1'], r['country']].where((e) => e != null).join('، ')),
                                      onTap: () {
                                        st.add(City(r['name'], (r['latitude'] as num).toDouble(), (r['longitude'] as num).toDouble()));
                                        Navigator.pop(context);
                                      }),
                              ]
                            : [
                                Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4), child: Text(st.t('saved'), style: TextStyle(fontSize: 13, color: wh(.6)))),
                                for (var i = 0; i < st.cities.length; i++)
                                  ListTile(
                                      leading: Icon(i == st.idx ? Icons.location_on_rounded : Icons.location_on_outlined),
                                      title: Text(st.nm(st.cities[i])),
                                      trailing: st.cities.length > 1 ? IconButton(icon: const Icon(Icons.close_rounded, size: 20), onPressed: () => st.remove(i)) : null,
                                      onTap: () { st.sel(i); Navigator.pop(context); }),
                              ])),
                  ])))));
}
