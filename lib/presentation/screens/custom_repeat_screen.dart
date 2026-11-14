import 'package:flutter/material.dart';
import '../../domain/entities/alarm.dart';

class CustomRepeatPreset {
  final String id;
  final String title;
  final RepeatRule rule;

  const CustomRepeatPreset({
    required this.id,
    required this.title,
    required this.rule,
  });
}

class CustomRepeatScreen extends StatefulWidget {
  final RepeatRule initialRule;

  const CustomRepeatScreen({super.key, required this.initialRule});

  static const List<CustomRepeatPreset> presets = [
    CustomRepeatPreset(
      id: 'alternate_days',
      title: 'Repeat on alternate days',
      rule: RepeatRule(
        frequency: RepeatFrequency.custom,
        interval: 2,
        customUnit: CustomRepeatUnit.days,
        customPreset: 'alternate_days',
      ),
    ),
    CustomRepeatPreset(
      id: 'every_3_days',
      title: 'Repeat every 3 days',
      rule: RepeatRule(
        frequency: RepeatFrequency.custom,
        interval: 3,
        customUnit: CustomRepeatUnit.days,
        customPreset: 'every_3_days',
      ),
    ),
    CustomRepeatPreset(
      id: 'every_2_weeks',
      title: 'Repeat every 2 weeks',
      rule: RepeatRule(
        frequency: RepeatFrequency.custom,
        interval: 2,
        customUnit: CustomRepeatUnit.weeks,
        customPreset: 'every_2_weeks',
      ),
    ),
    CustomRepeatPreset(
      id: 'quarterly',
      title: 'Repeat every 3 months (quarterly)',
      rule: RepeatRule(
        frequency: RepeatFrequency.custom,
        interval: 3,
        customUnit: CustomRepeatUnit.months,
        customPreset: 'quarterly',
      ),
    ),
    CustomRepeatPreset(
      id: 'last_day_of_month',
      title: 'Repeat last day of every month',
      rule: RepeatRule(
        frequency: RepeatFrequency.custom,
        interval: 1,
        customUnit: CustomRepeatUnit.months,
        lastDayOfMonth: true,
        customPreset: 'last_day_of_month',
      ),
    ),
    CustomRepeatPreset(
      id: '2nd_saturday_of_month',
      title: 'Repeat on 2nd Saturday of every month',
      rule: RepeatRule(
        frequency: RepeatFrequency.custom,
        interval: 1,
        customUnit: CustomRepeatUnit.months,
        weekdays: [DateTime.saturday],
        nthWeekday: 2,
        customPreset: '2nd_saturday_of_month',
      ),
    ),
  ];

  @override
  State<CustomRepeatScreen> createState() => _CustomRepeatScreenState();
}

class _CustomRepeatScreenState extends State<CustomRepeatScreen> {
  late String _selectedPresetId;
  late int _customInterval;
  late CustomRepeatUnit _customUnit;

  @override
  void initState() {
    super.initState();
    _selectedPresetId = widget.initialRule.customPreset ?? 'alternate_days';
    _customInterval = widget.initialRule.interval < 1 ? 2 : widget.initialRule.interval;
    _customUnit = widget.initialRule.customUnit;
  }

  void _selectPreset(CustomRepeatPreset preset) {
    setState(() => _selectedPresetId = preset.id);
    Navigator.of(context).pop(preset.rule);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Custom Repeat Options'),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(12, 8, 12, 24 + bottomInset),
          children: [
            ...CustomRepeatScreen.presets.map((preset) {
              final isSelected = _selectedPresetId == preset.id;
              return Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  onTap: () => _selectPreset(preset),
                  leading: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF00C853)
                          : Colors.grey.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  title: Text(
                    preset.title,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              );
            }),
            const Divider(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Text(
                'Or set a custom interval:',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Text('Repeat every:'),
                        const SizedBox(width: 12),
                        DropdownButton<int>(
                          value: _customInterval.clamp(1, 30),
                          items: List.generate(
                            30,
                            (i) => DropdownMenuItem(
                              value: i + 1,
                              child: Text('${i + 1}'),
                            ),
                          ),
                          onChanged: (v) {
                            if (v != null) setState(() => _customInterval = v);
                          },
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButton<CustomRepeatUnit>(
                            isExpanded: true,
                            value: _customUnit,
                            items: CustomRepeatUnit.values
                                .map(
                                  (u) => DropdownMenuItem(
                                    value: u,
                                    child: Text(u.name),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v != null) setState(() => _customUnit = v);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonal(
                        onPressed: () {
                          Navigator.of(context).pop(
                            RepeatRule(
                              frequency: RepeatFrequency.custom,
                              interval: _customInterval,
                              customUnit: _customUnit,
                              customPreset: 'custom_interval',
                            ),
                          );
                        },
                        child: Text('Apply Every $_customInterval ${_customUnit.name}'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
