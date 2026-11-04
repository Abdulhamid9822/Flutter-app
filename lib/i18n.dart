import 'package:flutter/material.dart' as m;
import 'package:flutter/widgets.dart' show ValueNotifier, ValueListenableBuilder;
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ilova tili: Poster sozlamasidagi til serverdan keladi (uz | ru | en).
class AppLang {
  static final ValueNotifier<String> lang = ValueNotifier('uz');
  static bool manual = false;
  static String get code => lang.value;

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    lang.value = _valid(p.getString('lang'));
    manual = p.getBool('lang_manual') ?? false;
    await initializeDateFormatting();
  }

  /// Foydalanuvchi qo'lda tanlagan til (serverdagi tildan ustun turadi).
  static Future<void> choose(String v) async {
    manual = true;
    final p = await SharedPreferences.getInstance();
    await p.setBool('lang_manual', true);
    await _store(v);
  }

  /// Poster sozlamasidagi til: faqat qo'lda tanlanmagan bo'lsa qo'llanadi.
  static Future<void> set(String? v) async {
    if (manual) return;
    await _store(v);
  }

  static Future<void> _store(String? v) async {
    final n = _valid(v);
    if (n == lang.value) return;
    lang.value = n;
    final p = await SharedPreferences.getInstance();
    await p.setString('lang', n);
  }

  static String _valid(String? v) => (v == 'ru' || v == 'en') ? v! : 'uz';
}

/// Til tanlash: O'zbekcha / Русский / English.
class LangPicker extends m.StatelessWidget {
  const LangPicker({super.key});

  @override
  m.Widget build(m.BuildContext context) => ValueListenableBuilder<String>(
        valueListenable: AppLang.lang,
        builder: (_, cur, _) => m.SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            m.ButtonSegment(value: 'uz', label: m.Text('O\'zbekcha', maxLines: 1)),
            m.ButtonSegment(value: 'ru', label: m.Text('Русский', maxLines: 1)),
            m.ButtonSegment(value: 'en', label: m.Text('English', maxLines: 1)),
          ],
          selected: {cur},
          onSelectionChanged: (s) => AppLang.choose(s.first),
        ),
      );
}

// uz -> [ru, en]
const Map<String, List<String>> _dict = {
  'Xodim': ['Сотрудник', 'Employee'],
  'Filial admini': ['Админ филиала', 'Branch admin'],
  'Super admin': ['Владелец', 'Owner'],
  'Xatolik': ['Ошибка', 'Error'],
  'Serverga ulanib bo\'lmadi. Internet va server manzilini tekshiring.': [
    'Не удалось подключиться к серверу. Проверьте интернет и адрес сервера.',
    'Cannot reach the server. Check your internet and server address.'
  ],
  'Erta ketish': ['Ранний уход', 'Leaving early'],
  'Kech kelish': ['Опоздание', 'Arriving late'],
  'Tasdiqlangan': ['Одобрена', 'Approved'],
  'Rad etilgan': ['Отклонена', 'Rejected'],
  'Kutilmoqda': ['Ожидает', 'Pending'],
  'Ariza': ['Заявка', 'Request'],
  'Hammasi': ['Все', 'All'],
  'Arizalar yo\'q': ['Заявок нет', 'No requests'],
  'Tasdiqlangan: jarima qo\'llanmaydi': ['Одобрено: штраф не применяется', 'Approved: no penalty'],
  'Ariza vaqtiga amal qilgan: jarima qo\'llanmaydi': [
    'Время заявки соблюдено: штраф не применяется',
    'Requested time met: no penalty'
  ],
  'Ariza vaqtiga amal qilmagan: jarima qo\'llanadi': [
    'Время заявки не соблюдено: штраф применяется',
    'Requested time not met: penalty applies'
  ],
  'Rad etish': ['Отклонить', 'Reject'],
  'Tasdiqlash': ['Одобрить', 'Approve'],
  'Sababni yozing': ['Укажите причину', 'Enter a reason'],
  'Yangi ariza': ['Новая заявка', 'New request'],
  'Shu vaqtdan oldin ketsangiz, jarima qo\'llanadi.': [
    'Если уйдёте раньше этого времени, будет штраф.',
    'A penalty applies if you leave before this time.'
  ],
  'Shu vaqtdan kech qolsangiz, jarima qo\'llanadi.': [
    'Если опоздаете позже этого времени, будет штраф.',
    'A penalty applies if you arrive after this time.'
  ],
  'Sabab': ['Причина', 'Reason'],
  'Yuborish': ['Отправить', 'Send'],
  'Xodimga javob (ixtiyoriy)': ['Ответ сотруднику (необязательно)', 'Reply to employee (optional)'],
  'Davomat Pro': ['Davomat Pro', 'Davomat Pro'],
  'DAVOMAT PRO': ['DAVOMAT PRO', 'DAVOMAT PRO'],
  'Xodimlar davomati va oyligi': ['Посещаемость и зарплата сотрудников', 'Employee attendance and salary'],
  'Telefon raqam': ['Номер телефона', 'Phone number'],
  'PIN': ['PIN', 'PIN'],
  'Server manzili': ['Адрес сервера', 'Server address'],
  'Kirish': ['Войти', 'Sign in'],
  'Server sozlamasini yashirish': ['Скрыть настройки сервера', 'Hide server settings'],
  'Server sozlamasi': ['Настройки сервера', 'Server settings'],
  'Arizalar': ['Заявки', 'Requests'],
  'ARIZALAR': ['ЗАЯВКИ', 'REQUESTS'],
  'Bosh sahifa': ['Главная', 'Home'],
  'BOSH SAHIFA': ['ГЛАВНАЯ', 'HOME'],
  'Oylik': ['Зарплата', 'Salary'],
  'Tarix': ['История', 'History'],
  'MENING OYLIGIM': ['МОЯ ЗАРПЛАТА', 'MY SALARY'],
  'DAVOMAT TARIXI': ['ИСТОРИЯ ПОСЕЩАЕМОСТИ', 'ATTENDANCE HISTORY'],
  'Xodimlar': ['Сотрудники', 'Employees'],
  'XODIMLAR RO\'YXATI': ['СПИСОК СОТРУДНИКОВ', 'EMPLOYEE LIST'],
  'Davomat': ['Посещаемость', 'Attendance'],
  'DAVOMAT': ['ПОСЕЩАЕМОСТЬ', 'ATTENDANCE'],
  'Filiallar': ['Филиалы', 'Branches'],
  'FILIALLAR': ['ФИЛИАЛЫ', 'BRANCHES'],
  'Sozlamalar': ['Настройки', 'Settings'],
  'SOZLAMALAR': ['НАСТРОЙКИ', 'SETTINGS'],
  'BELGILANGAN OYLIK': ['УСТАНОВЛЕННАЯ ЗАРПЛАТА', 'SET SALARY'],
  'Belgilanmagan': ['Не указано', 'Not set'],
  'Hisoblangan': ['Начислено', 'Earned'],
  'To\'langan': ['Выплачено', 'Paid'],
  'Oldingi oy balansi': ['Баланс прошлого месяца', 'Previous month balance'],
  'To\'lanishi kerak': ['К выплате', 'Amount due'],
  'Ortiqcha to\'langan': ['Переплата', 'Overpaid'],
  'Hisob-kitob teng': ['Расчёт сведён', 'Settled'],
  'Bu oy hisobi hali veb-hisobotda saqlanmagan.': [
    'Расчёт за этот месяц ещё не сохранён в веб-отчёте.',
    'This month is not saved in the web report yet.'
  ],
  'To\'lovlarni olib bo\'lmadi': ['Не удалось получить выплаты', 'Could not load payments'],
  'Bu davrda davomat yo\'q': ['За этот период нет посещаемости', 'No attendance for this period'],
  'Xodim qidirish': ['Поиск сотрудника', 'Search employee'],
  'Barchasi': ['Все', 'All'],
  'Jami to\'langan': ['Всего выплачено', 'Total paid'],
  'Biriktirilmagan': ['Не привязан', 'Unassigned'],
  'PIN almashtirish': ['Смена PIN', 'Change PIN'],
  'Eski PIN': ['Старый PIN', 'Old PIN'],
  'Yangi PIN (4-6 raqam)': ['Новый PIN (4–6 цифр)', 'New PIN (4-6 digits)'],
  'Bekor': ['Отмена', 'Cancel'],
  'Dam olish': ['Выходной', 'Day off'],
  'Dam olish kuni berish': ['Назначить выходной', 'Give a day off'],
  'Dam olishni bekor qilish': ['Отменить выходной', 'Cancel day off'],
  'Bekor qilish': ['Отменить', 'Cancel'],
  'Necha kun': ['Сколько дней', 'How many days'],
  'Izoh (ixtiyoriy)': ['Комментарий (необязательно)', 'Note (optional)'],
  'Jarima': ['Штраф', 'Penalty'],
  'Izoh': ['Комментарий', 'Note'],
  'Ariza tasdiqlangan — jarima yo\'q': ['Заявка одобрена — штрафа нет', 'Request approved — no penalty'],
  'Saqlash': ['Сохранить', 'Save'],
  'PIN o\'zgartirildi': ['PIN изменён', 'PIN changed'],
  'Yorqin mavzu': ['Светлая тема', 'Light theme'],
  'Qorong\'u mavzu': ['Тёмная тема', 'Dark theme'],
  'Push sinash': ['Проверка push', 'Test push'],
  'Sinalmoqda...': ['Проверка...', 'Testing...'],
  'Push sinov': ['Проверка push', 'Push test'],
  'Chiqish': ['Выйти', 'Sign out'],
  'Bugun': ['Сегодня', 'Today'],
  'Hafta': ['Неделя', 'Week'],
  'Oy': ['Месяц', 'Month'],
  'Oraliq': ['Период', 'Range'],
  'Ma\'lumot yo\'q': ['Нет данных', 'No data'],
  'Keldi': ['Пришёл', 'Present'],
  'Kechikdi': ['Опоздал', 'Late'],
  'Kelmadi': ['Отсутствует', 'Absent'],
  'Ariza va qarorlar haqida bildirishnomalar': ['Уведомления о заявках и решениях', 'Request and decision notifications'],
  'Yarim kun': ['Полдня', 'Half day'],
  'Qo\'shimcha': ['Доп. смена', 'Extra'],
  'Ta\'til': ['Отпуск', 'Vacation'],
  'Kasal': ['Больничный', 'Sick'],
  'Jami xodimlar': ['Всего сотрудников', 'Total employees'],
  'Davomat diagrammasi': ['Диаграмма посещаемости', 'Attendance chart'],
  'Kunlik hisobot jadvali': ['Таблица дневного отчёта', 'Daily report table'],
  'KUNLIK HISOBOT': ['ДНЕВНОЙ ОТЧЁТ', 'DAILY REPORT'],
  'Shu oy oyligi': ['Зарплата за месяц', 'This month salary'],
  'Shu oy davomati': ['Посещаемость за месяц', 'This month attendance'],
  'To\'liq oylik va tarix': ['Полная зарплата и история', 'Full salary and history'],
  'Qayta urinish': ['Повторить', 'Retry'],
  'Avtorizatsiya talab qilinadi': ['Требуется авторизация', 'Authorization required'],
  'Sessiya tugagan. Qayta kiring.': ['Сессия истекла. Войдите снова.', 'Session expired. Sign in again.'],
  'Xodim topilmadi yoki ruxsat yo\'q': ['Сотрудник не найден или нет доступа', 'Employee not found or access denied'],
  'Telefon yoki PIN noto\'g\'ri': ['Неверный телефон или PIN', 'Wrong phone or PIN'],
  'Juda ko\'p urinish. 15 daqiqadan keyin qayta urining.': [
    'Слишком много попыток. Повторите через 15 минут.',
    'Too many attempts. Try again in 15 minutes.'
  ],
  'Eski PIN noto\'g\'ri': ['Неверный старый PIN', 'Wrong old PIN'],
  'PIN 4-6 raqamdan iborat bo\'lishi kerak': ['PIN должен содержать 4–6 цифр', 'PIN must be 4-6 digits'],
  'Xodim tanlanmagan': ['Сотрудник не выбран', 'No employee selected'],
  'Ruxsat yo\'q': ['Нет доступа', 'Access denied'],
  'Ariza faqat xodim uchun': ['Заявки подаёт только сотрудник', 'Only employees can submit requests'],
  'Ketish vaqtini kiriting': ['Укажите время ухода', 'Enter the leaving time'],
  'Kelish vaqtini kiriting': ['Укажите время прихода', 'Enter the arrival time'],
  'Ariza ma\'lumotlari noto\'g\'ri': ['Неверные данные заявки', 'Invalid request data'],
  'Sana oralig\'i noto\'g\'ri': ['Неверный диапазон дат', 'Invalid date range'],
  'Sababni yozing (500 belgigacha)': ['Укажите причину (до 500 символов)', 'Enter a reason (up to 500 characters)'],
  'Bu sana uchun ariza allaqachon yuborilgan': ['Заявка на эту дату уже подана', 'A request for this date already exists'],
  'Qaror noto\'g\'ri': ['Неверное решение', 'Invalid decision'],
  'Ariza topilmadi': ['Заявка не найдена', 'Request not found'],
  'Noma\'lum amal': ['Неизвестное действие', 'Unknown action'],
  'Server xatosi': ['Ошибка сервера', 'Server error'],
  'Sinov': ['Проверка', 'Test'],
  'Push ishlayapti': ['Push работает', 'Push works'],
};

// Interpolatsiyali matnlar uchun bo'laklar (uz -> [ru, en]); uzunlari birinchi.
const Map<String, List<String>> _frag = {
  'Ketish vaqti (so\'ralgan)': ['Время ухода (запрошено)', 'Leaving time (requested)'],
  'Kelish vaqti (so\'ralgan)': ['Время прихода (запрошено)', 'Arrival time (requested)'],
  'Ketish vaqti': ['Время ухода', 'Leaving time'],
  'Kelish vaqti': ['Время прихода', 'Arrival time'],
  'Bildirishnomani kuting': ['Ожидайте уведомление', 'Wait for the notification'],
  'Erta ketgan': ['Ушёл раньше', 'Left early'],
  'Belgilanmagan': ['Не указано', 'Not set'],
  'Biriktirilmagan': ['Не привязан', 'Unassigned'],
  'Yuborilgan': ['Отправлено', 'Sent'],
  'Yuborildi': ['Отправлено', 'Sent'],
  'Kechikish': ['Опоздание', 'Late by'],
  'Kechikdi': ['Опоздал', 'Late'],
  'Kelmadi': ['Отсутствует', 'Absent'],
  'Haqiqiy': ['Фактически', 'Actual'],
  'To\'lovlar': ['Выплаты', 'Payments'],
  'Keldi': ['Пришёл', 'Present'],
  'Kirdi': ['Вход', 'In'],
  'Chiqdi': ['Выход', 'Out'],
  'kirdi': ['вход', 'in'],
  'chiqdi': ['выход', 'out'],
  'Sana': ['Дата', 'Date'],
  'Sabab': ['Причина', 'Reason'],
  'Qaror': ['Решение', 'Decision'],
  'Javob': ['Ответ', 'Reply'],
  'Filial': ['Филиал', 'Branch'],
  'daqiqa': ['мин', 'min'],
  'xodim': ['сотр.', 'staff'],
  'soat': ['час', 'hour'],
  'smena': ['смена', 'shift'],
  'so\'m': ['сум', 'UZS'],
};

final List<MapEntry<RegExp, List<String>>> _fragRe = (_frag.entries.toList()
      ..sort((a, b) => b.key.length.compareTo(a.key.length)))
    .map((e) => MapEntry(
        RegExp('(?<![\\p{L}\'])${RegExp.escape(e.key)}(?![\\p{L}\'])', unicode: true), e.value))
    .toList();

final Map<String, List<String>> _lower = {
  for (final e in _dict.entries) e.key.toLowerCase(): e.value,
};

String tr(String s) {
  final code = AppLang.code;
  if (code == 'uz' || s.isEmpty) return s;
  final i = code == 'ru' ? 0 : 1;
  final hit = _dict[s];
  if (hit != null) return hit[i];
  final up = s == s.toUpperCase() && s != s.toLowerCase();
  final lo = _lower[s.toLowerCase()];
  if (lo != null) return up ? lo[i].toUpperCase() : lo[i];
  var out = s;
  for (final e in _fragRe) {
    out = out.replaceAllMapped(e.key, (_) => e.value[i]);
  }
  return out;
}

/// Material `Text` o'rniga: matn tanlangan tilga avtomatik tarjima qilinadi.
class Text extends m.StatelessWidget {
  final String data;
  final m.TextStyle? style;
  final m.TextAlign? textAlign;
  final int? maxLines;
  final m.TextOverflow? overflow;
  final bool? softWrap;

  const Text(this.data,
      {super.key, this.style, this.textAlign, this.maxLines, this.overflow, this.softWrap});

  @override
  m.Widget build(m.BuildContext context) => m.Text(tr(data),
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
      softWrap: softWrap);
}
