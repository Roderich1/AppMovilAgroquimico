import 'operation_id.dart';
import 'sync_types.dart';

/// La respuesta de referencias no respeta la whitelist cerrada de F05-SYNC-07.
class CentralReferencesFormatException implements Exception {
  const CentralReferencesFormatException();
  @override
  String toString() =>
      'Las referencias del sindicato no tienen el formato esperado.';
}

/// Campaña central del tenant, tal como la publica `GET /sync/v1/references`.
class CentralCampaign {
  const CentralCampaign({
    required this.ref,
    required this.name,
    required this.status,
    required this.startDate,
    required this.endDate,
    required this.acceptsContributions,
  });

  final String ref;
  final String name;
  final String status;
  final String startDate;
  final String? endDate;

  /// `ABIERTA` e `isActive` en Central (F06 §6).
  final bool acceptsContributions;
}

/// Producto central del tenant. [baseUnit] sólo existe para L y KG.
class CentralProduct {
  const CentralProduct({
    required this.ref,
    required this.name,
    required this.unit,
    required this.baseUnit,
    required this.isActive,
    required this.linkable,
  });

  final String ref;
  final String name;
  final String unit;
  final BaseUnit? baseUnit;
  final bool isActive;
  final bool linkable;
}

class CentralReferences {
  const CentralReferences(this.campaigns, this.products);

  final List<CentralCampaign> campaigns;
  final List<CentralProduct> products;

  CentralCampaign? campaign(String ref) {
    for (final campaign in campaigns) {
      if (campaign.ref == ref) return campaign;
    }
    return null;
  }

  CentralProduct? product(String ref) {
    for (final product in products) {
      if (product.ref == ref) return product;
    }
    return null;
  }

  static const _rootKeys = {'contractVersion', 'campaigns', 'products'};
  static const _campaignKeys = {
    'campaign_ref',
    'name',
    'status',
    'start_date',
    'end_date',
    'accepts_contributions',
  };
  static const _productKeys = {
    'product_ref',
    'name',
    'unit',
    'base_unit',
    'is_active',
    'linkable',
  };

  /// Acepta sólo la forma exacta: claves conocidas, tipos correctos y
  /// referencias canónicas. Cualquier otra cosa se rechaza entera, sin
  /// guardar nada parcial ni conservar campos ajenos a la whitelist.
  factory CentralReferences.fromJson(Map<String, dynamic> json) {
    _exactKeys(json, _rootKeys);
    if (json['contractVersion'] != 1) _invalid();
    final campaigns = _list(json['campaigns']).map((raw) {
      final item = _object(raw);
      _exactKeys(item, _campaignKeys);
      return CentralCampaign(
        ref: _ref(item['campaign_ref']),
        name: _text(item['name']),
        status: _text(item['status']),
        startDate: _text(item['start_date']),
        endDate: item['end_date'] == null ? null : _text(item['end_date']),
        acceptsContributions: _bool(item['accepts_contributions']),
      );
    }).toList();
    final products = _list(json['products']).map((raw) {
      final item = _object(raw);
      _exactKeys(item, _productKeys);
      final unit = _text(item['unit']);
      final baseUnit = item['base_unit'] == null
          ? null
          : BaseUnit.fromCode(item['base_unit']) ?? _invalid();
      final linkable = _bool(item['linkable']);
      // La base debe ser la que corresponde a la unidad central: Mobile no
      // acepta una equivalencia que no puede comprobar.
      if (baseUnit != BaseUnit.forCentralUnit(unit) ||
          linkable != (baseUnit != null)) {
        _invalid();
      }
      return CentralProduct(
        ref: _ref(item['product_ref']),
        name: _text(item['name']),
        unit: unit,
        baseUnit: baseUnit,
        isActive: _bool(item['is_active']),
        linkable: linkable,
      );
    }).toList();
    return CentralReferences(campaigns, products);
  }

  static Never _invalid() => throw const CentralReferencesFormatException();

  static void _exactKeys(Map<String, dynamic> json, Set<String> keys) {
    if (json.length != keys.length || !keys.containsAll(json.keys)) _invalid();
  }

  static List<dynamic> _list(Object? value) =>
      value is List<dynamic> ? value : _invalid();

  static Map<String, dynamic> _object(Object? value) =>
      value is Map<String, dynamic> ? value : _invalid();

  static String _text(Object? value) =>
      value is String && value.isNotEmpty ? value : _invalid();

  static bool _bool(Object? value) => value is bool ? value : _invalid();

  static String _ref(Object? value) =>
      value is String && canonicalUuid.hasMatch(value) ? value : _invalid();
}
