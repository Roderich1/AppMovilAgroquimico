"""Instantánea de solo lectura de la base copiada del POCO (diagnóstico F09).

Conteos, existencias por producto y dueño, compras y movimientos de cuentas.
Sólo datos sintéticos de la DEMO; ningún texto dictado.
"""
import sqlite3
import sys

c = sqlite3.connect(sys.argv[1])
q = lambda sql, *a: c.execute(sql, a).fetchall()

for t in ['purchases', 'purchase_items', 'inventory_lots', 'inventory_movements',
          'account_transactions', 'provider_payments', 'applications',
          'application_plans', 'voice_evidence_consent']:
    print(f'{t}={q(f"select count(*) from {t}")[0][0]}', end=' ')
print('integridad=' + q('pragma integrity_check')[0][0])

print('-- existencias (suma de movimientos, unidades base) por producto y dueño')
for name, unit, owner, total in q('''
    select p.name, p.unit, coalesce(pe.name, '-'), sum(m.quantity_signed)
    from inventory_movements m join products p on p.id = m.product_id
    left join persons pe on pe.id = m.owner_person_id
    group by p.id, m.owner_person_id order by p.name, pe.name'''):
    print(f'  {name} [{unit}] {owner}: {total}')

print('-- últimas compras')
for row in q('''select id, supplier_id, purchase_date, total_bob_minor, status,
                reversed_at from purchases order by id desc limit 3'''):
    print('  compra', row)
    for it in q('''select product_id, quantity_base, currency_code,
                   original_unit_price_minor, subtotal_bob_minor
                   from purchase_items where purchase_id = ?''', row[0]):
        print('    ítem', it)
print('-- cuentas: suma por persona')
for name, total, n in q('''select coalesce(pe.name, '-'), sum(a.amount_bob_minor_signed), count(*)
                           from account_transactions a left join persons pe on pe.id = a.person_id
                           group by a.person_id order by pe.name'''):
    print(f'  {name}: {total} ({n} mov.)')
print('-- pagos a proveedor:', q('select count(*), coalesce(sum(amount_bob_minor),0) from provider_payments where reversed_at is null')[0])
