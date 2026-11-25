import 'package:flutter/material.dart';

import '../../../domain/money.dart';
import '../../../voice_draft/application/voice_application_draft.dart';
import '../../theme/agro_theme.dart';
import '../../voice/voice_form_dictation.dart';
import '../../widgets/adaptive_entity_picker.dart';
import '../../widgets/agro_ui.dart';
import '../../widgets/common.dart' show personRoleLabel;
import 'application_form_state.dart';
import 'application_form_voice_adapter.dart';

List<Widget> buildApplicationVoiceEntry({
  required ApplicationFormState state,
  required VoiceFormDictation<VoiceApplicationDraft>? voice,
  required VoidCallback onOpenVoice,
  required VoidCallback onDismissVoiceBanner,
}) {
  if (!state.voiceStep || state.showVoice) return const [];
  if (voice != null && state.voiceBanner) {
    return [
      VoiceResultBanner(
        dictation: voice,
        onDictateMore: state.saving ? null : onOpenVoice,
        onDismiss: onDismissVoiceBanner,
      ),
      const SizedBox(height: 12),
    ];
  }
  return [
    Align(
      alignment: Alignment.centerLeft,
      child: PillButton(
        key: const Key('aplicacion-completar-voz'),
        icon: Icons.mic_none_outlined,
        label: 'Completar por voz',
        onPressed: state.saving ? null : onOpenVoice,
      ),
    ),
    const SizedBox(height: 12),
  ];
}

Widget _fixedRow(Key key, String label, String value) => ValueRow(
  key: key,
  label: label,
  value: value,
  onTap: null,
  trailing: const SizedBox.shrink(),
);

List<Widget> buildApplicationWhoStep(
  BuildContext context, {
  required ApplicationFormState state,
  required ApplicationCatalogs data,
  required TextEditingController areaController,
  required VoiceFormDictation<VoiceApplicationDraft>? voice,
  required VoidCallback onOpenVoice,
  required VoidCallback onDismissVoiceBanner,
  required ValueChanged<Map<String, Object?>?> onSelectPerson,
  required Future<Map<String, Object?>?> Function() onCreatePerson,
  required ValueChanged<Map<String, Object?>?> onSelectFarm,
  required Future<Map<String, Object?>?> Function() onCreateFarm,
  required VoidCallback onPickDate,
  required ValueChanged<String> onAreaChanged,
}) {
  final person = state.person(data);
  final farms = data.farms
      .where(
        (f) => state.personId == null || f['owner_person_id'] == state.personId,
      )
      .toList();
  final farm = state.farm(data);
  return [
    Semantics(
      header: true,
      child: const Text('¿Dónde aplicó?', style: AgroText.h1),
    ),
    const SizedBox(height: 12),
    ...buildApplicationVoiceEntry(
      state: state,
      voice: voice,
      onOpenVoice: onOpenVoice,
      onDismissVoiceBanner: onDismissVoiceBanner,
    ),
    AgroGroup(
      children: [
        if (state.planId != null) ...[
          _fixedRow(
            const Key('application-plan-person'),
            'Persona del plan',
            person?['name']?.toString() ?? '',
          ),
          _fixedRow(
            const Key('application-plan-farm'),
            'Chaco del plan',
            farm?['name']?.toString() ?? '',
          ),
        ] else if (state.personalMode)
          ...const <Widget>[]
        else
          AdaptiveEntityPicker<Map<String, Object?>>(
            rowStyle: true,
            label: applicationPersonLabel,
            hint: 'Responsable del chaco · se usan sus productos',
            hintKey: const Key('application-person-hint'),
            items: data.people,
            value: person,
            labelOf: (p) => p['name'] as String,
            secondaryOf: (p) => personRoleLabel(p['role']),
            onChanged: onSelectPerson,
            createLabel: 'Agregar persona',
            onCreate: onCreatePerson,
          ),
        if (state.planId == null)
          AdaptiveEntityPicker<Map<String, Object?>>(
            rowStyle: true,
            label: 'Chaco',
            items: farms,
            value: farm,
            labelOf: (f) => f['name'] as String,
            secondaryOf: (f) => formatHectares(f['area_m2'] as int),
            placeholder: state.personId == null
                ? 'Elija primero la persona'
                : 'Elegir',
            onChanged: onSelectFarm,
            enabled: state.personId != null,
            createLabel: 'Crear chaco',
            onCreate: onCreateFarm,
            badge: VoiceMarkBadge(
              dictation: voice,
              slot: const SlotRef.header('farm'),
              current: state.farmId,
            ),
          ),
        ValueRow(
          key: const Key('application-date'),
          label: 'Fecha',
          value: applicationDayLabel(state.effectiveDay),
          onTap: state.saving ? null : onPickDate,
        ),
      ],
    ),
    if (state.planId == null) ...[
      VoiceSlotMark(
        dictation: voice,
        slot: const SlotRef.header('farm'),
        current: state.farmId,
        currentDisplay: farm?['name']?.toString(),
        showMark: false,
      ),
      VoiceSlotMark(
        dictation: voice,
        slot: const SlotRef.header('plan'),
        current: null,
        showMark: false,
      ),
    ],
    const SizedBox(height: 12),
    TextField(
      key: const Key('application-area'),
      controller: areaController,
      onChanged: onAreaChanged,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: AgroText.input,
      decoration: InputDecoration(
        labelText: state.personalMode ? 'Superficie tratada' : 'Área tratada',
        floatingLabelBehavior: FloatingLabelBehavior.always,
        suffixText: 'ha',
        suffixStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AgroColors.muted,
        ),
        helperText: farm == null
            ? 'Se toma del chaco; puede cambiarla.'
            : 'El chaco tiene ${formatHectares(farm['area_m2'] as int)}; '
                  'puede cambiarla.',
        helperMaxLines: 2,
        errorText: state.areaError,
        errorMaxLines: 3,
      ),
    ),
    VoiceSlotMark(
      dictation: voice,
      slot: const SlotRef.header('area'),
      current: ApplicationFormVoiceAdapter.areaCanon(areaController.text),
      currentDisplay: areaController.text,
    ),
    if (state.lines.isNotEmpty && voice != null && !voice.busy)
      Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(
          'Productos en la mezcla: ${state.lines.length} (paso 2).',
          key: const Key('aplicacion-lineas-paso2'),
          style: AgroText.detail,
        ),
      ),
  ];
}
