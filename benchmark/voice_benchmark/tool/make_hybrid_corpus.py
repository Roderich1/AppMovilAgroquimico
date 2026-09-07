# Genera assets/corpus_hybrid.json — corpus de la Fase 0-bis (ADR-004).
#
# El corpus de la Fase 0 (assets/corpus.json) NO se toca: sigue siendo la
# referencia comparable con lo ya medido. Este es otro, versionado aparte, con
# las categorías A–G que pide EVOLUTION-3_HYBRID_ENGINE_BENCHMARK_PLAN.md.
#
# Regla dura: ajuste y aceptación no comparten ni una frase. El script lo
# comprueba y falla si alguien la rompe.
import io, json, collections, unicodedata

S = []

def add(split, cat, intent, text, expected, slots=None, conditions=None,
        tags=None, note=None):
    S.append(dict(split=split, category=cat, intent=intent, text=text,
                  expected=expected, slots=slots or {},
                  conditions=conditions or [], tags=tags or [], note=note))

AJ, AC = "ajuste", "aceptacion"

# ----------------------------------------------------------------- A: acciones
add(AJ,"A","compra","Anotar una compra nueva.","incompleto",{},[],["frase_corta"],
    "Intencion sola: faltan producto, cantidad y precio.")
add(AJ,"A","aplicacion","Ejecutar el plan del chaco.","incompleto",{},[],["frase_corta"])
add(AJ,"A","pago","Anotar un pago al proveedor.","incompleto",{},[],["frase_corta"])
add(AJ,"A","mezclada","Seguir hablando.","rechazado",{},[],["control_ui"],
    "Es una orden de la pantalla, no un dato. No debe convertirse en texto de negocio.")
add(AC,"A","compra","Quiero registrar una compra.","incompleto",{},[],["frase_corta"])
add(AC,"A","aplicacion","Voy a aplicar la planificacion.","incompleto",{},[],["frase_corta"])
add(AC,"A","pago","Necesito registrar un pago.","incompleto",{},[],["frase_corta"])
add(AC,"A","mezclada","Descartar todo lo dictado.","rechazado",{},[],["control_ui"])

# ------------------------------------------------- B: dictado largo de compras
add(AJ,"B","compra","Compra de cincuenta litros de Bellator a ciento ochenta y seis bolivianos el litro.",
    "listo",{"producto":"Bellator","cantidad":"50","unidad":"litro","precio":"186","moneda":"BOB"},
    [],["un_producto","precio_entero","bob"])
add(AJ,"B","compra","Compre veinticinco kilos de Mancozeb a noventa con cincuenta bolivianos el kilo.",
    "listo",{"producto":"Mancozeb","cantidad":"25","unidad":"kilo","precio":"90.50","moneda":"BOB"},
    [],["un_producto","precio_decimal"])
add(AJ,"B","compra","Compra de diez litros de Paraquat y veinte kilos de Mancozeb del proveedor Agro Norte.",
    "listo",{"producto":"Paraquat|Mancozeb","cantidad":"10|20","unidad":"litro|kilo","proveedor":"Agro Norte"},
    [],["dos_productos","proveedor_al_final"])
add(AJ,"B","compra","Del proveedor Agro Norte, cuarenta litros de Glifosato a doce dolares el litro.",
    "listo",{"producto":"Glifosato","cantidad":"40","unidad":"litro","precio":"12","moneda":"USD","proveedor":"Agro Norte"},
    [],["un_producto","usd","proveedor_al_inicio"])
add(AC,"B","compra","Registrar compra de ocho unidades de Expansive a treinta y cuatro bolivianos cada una.",
    "listo",{"producto":"Expansive","cantidad":"8","unidad":"unidad","precio":"34","moneda":"BOB"},
    [],["un_producto","unidades"])
add(AC,"B","compra","Compra de cien litros de Paraquat a quince con setenta y cinco bolivianos el litro.",
    "listo",{"producto":"Paraquat","cantidad":"100","unidad":"litro","precio":"15.75","moneda":"BOB"},
    [],["un_producto","precio_decimal"])
add(AC,"B","compra",
    "Compra de treinta litros de Bellator, quince kilos de Mancozeb, doce litros de Paraquat y "
    "seis unidades de Expansive.","listo",
    {"producto":"Bellator|Mancozeb|Paraquat|Expansive","cantidad":"30|15|12|6",
     "unidad":"litro|kilo|litro|unidad"},[],["cuatro_productos","frase_larga"])
add(AC,"B","compra",
    "Para la campana de verano, del proveedor Insumos del Este, compre veinte litros de Bellator, "
    "diez kilos de Mancozeb, cinco litros de Paraquat, ocho unidades de Expansive, doce litros de "
    "Glifosato, cuatro kilos de Lambdacialotrina, seis litros de Germispa y dos unidades de Germi cien.",
    "listo",{"producto":"Bellator|Mancozeb|Paraquat|Expansive|Glifosato|Lambdacialotrina|Germispa|Germi-100",
             "cantidad":"20|10|5|8|12|4|6|2","proveedor":"Insumos del Este","campana":"verano"},
    [],["ocho_productos","frase_muy_larga","campana_al_inicio"],
    "El caso peor de longitud. Mide si el motor se pierde al final de la frase.")
add(AC,"B","compra","Cincuenta litros de Bellator a ciento ochenta y seis bolivianos, todo queda asignado al administrador.",
    "listo",{"producto":"Bellator","cantidad":"50","precio":"186","propietario":"administrador"},
    [],["propietario_al_final"])

# ---------------------------------------- C: aplicaciones y planificacion
add(AJ,"C","aplicacion","Aplicar la planificacion del chaco Limoncitos.","listo",
    {"chaco":"Limoncitos"},[],["chaco_simple"])
add(AJ,"C","aplicacion","En el chaco Monte Verde use diez litros de Bellator en vez de los doce planificados.",
    "listo",{"chaco":"Monte Verde","producto":"Bellator","cantidad_real":"10","cantidad_plan":"12"},
    [],["real_vs_plan"])
add(AC,"C","aplicacion","Quiero aplicar la planificacion para el chaco Limoncitos.","listo",
    {"chaco":"Limoncitos"},[],["chaco_simple"])
add(AC,"C","aplicacion","Aplicar el plan del chaco Bajio Grande, pero solo alcanzo para la mitad del lote.",
    "ambiguo",{"chaco":"Bajio Grande","cantidad":"AMBIGUO"},[],["cantidad_vaga"],
    "«La mitad» no es una cantidad: debe bloquear, no inventar un numero.")
add(AC,"C","aplicacion","Aplicar la planificacion del chaco, el de siempre.","ambiguo",
    {"chaco":"AMBIGUO"},[],["chaco_ambiguo"],
    "No hay chaco identificable. No debe elegirse uno por proximidad.")
add(AC,"C","aplicacion","No hay suficiente Mancozeb en el deposito para cubrir el plan del chaco Limoncitos.",
    "rechazado",{"chaco":"Limoncitos","producto":"Mancozeb"},[],["stock_insuficiente"])

# ------------------------------------------------------------------ D: pagos
add(AJ,"D","pago","Registrar un pago de dos mil bolivianos.","incompleto",
    {"monto":"2000","moneda":"BOB"},[],["sin_persona"])
add(AJ,"D","pago","Pago de mil quinientos con veinticinco bolivianos para Jose Luis.","listo",
    {"persona":"Jose Luis","monto":"1500.25","moneda":"BOB"},[],["monto_decimal"])
add(AJ,"D","pago","Registra un pago para Jose Luis de dos mil bolivianos.","listo",
    {"persona":"Jose Luis","monto":"2000","moneda":"BOB"},[],["persona_simple","heredada_fase0"],
    "Heredada del corpus de la Fase 0 (AJ-026). Se conserva en ajuste, el mismo "
    "conjunto en el que ya estaba, para poder comparar contra lo medido en el POCO.")
add(AC,"D","pago","Pagar trescientos cincuenta dolares a Maria Elena.","listo",
    {"persona":"Maria Elena","monto":"350","moneda":"USD"},[],["usd"])
add(AC,"D","pago","Un pago para Jose, el del chaco de arriba, de ochocientos bolivianos.","ambiguo",
    {"persona":"AMBIGUO","monto":"800"},[],["homonimo"],
    "Hay mas de un Jose. La persona no puede autoresolverse.")
add(AC,"D","pago","Pago de cinco mil bolivianos a Maria Elena, aunque su deuda es de cuatro mil doscientos.",
    "ambiguo",{"persona":"Maria Elena","monto":"5000","excedente":"AMBIGUO"},[],["excedente"],
    "El excedente no se convierte en adelanto sin decision explicita.")

# --------------------------------------------------------- E: catalogo agricola
add(AJ,"E","compra","Veinte litros de Germispa.","listo",
    {"producto":"Germispa","cantidad":"20","unidad":"litro"},[],["catalogo"])
add(AJ,"E","compra","Diez unidades de Germi cien.","listo",
    {"producto":"Germi-100","cantidad":"10","unidad":"unidad"},[],["catalogo","alias_hablado"],
    "Se dicta «germi cien»; el catalogo lo registra como Germi-100.")
add(AJ,"E","compra","Quince litros de Lambdacialotrina.","listo",
    {"producto":"Lambdacialotrina","cantidad":"15","unidad":"litro"},[],["catalogo","palabra_larga"])
add(AC,"E","compra","Cinco unidades de Germi uno cero cero.","listo",
    {"producto":"Germi-100","cantidad":"5","unidad":"unidad"},[],["catalogo","alias_deletreado"],
    "Misma sustancia dictada cifra a cifra. No debe dar un producto distinto que «germi cien».")
add(AC,"E","compra","Doce litros de Expansiv.","listo",
    {"producto":"Expansive","cantidad":"12","unidad":"litro"},[],["catalogo","variante_pronunciacion"],
    "Se pronuncia sin la e final. Es el mismo producto del catalogo.")
add(AC,"E","compra","Treinta kilos de Mancozeb y diez litros de Paraquat.","listo",
    {"producto":"Mancozeb|Paraquat","cantidad":"30|10"},[],["catalogo","dos_productos"])
add(AC,"E","compra","Ocho litros de Bellator para el chaco Limoncitos.","listo",
    {"producto":"Bellator","cantidad":"8","chaco":"Limoncitos"},[],["catalogo"])

# ------------------------------------------------ F: negaciones y correcciones
add(AJ,"F","compra","No fueron doce, fueron dos.","ambiguo",
    {"cantidad":"2"},["correccion"],["negacion"],
    "La cantidad final es 2. Aceptar 12 seria el error caro.")
add(AJ,"F","compra","Borra Bellator.","rechazado",{},["correccion"],["negacion"])
add(AC,"F","compra","El precio no es ciento ochenta, es ciento ochenta y seis.","listo",
    {"precio":"186"},["correccion"],["negacion","precio"],
    "Debe quedar 186. Quedarse con 180 es el fallo tipico.")
add(AJ,"F","compra","De Bellator en realidad usamos diez litros.","listo",
    {"producto":"Bellator","cantidad":"10"},["correccion"],["negacion","heredada_fase0"],
    "Heredada del corpus de la Fase 0 (AJ-017), en su mismo conjunto.")
add(AC,"F","compra","Cincuenta litros de... no, esperen... cuarenta litros de Paraquat.","listo",
    {"producto":"Paraquat","cantidad":"40"},["pausas","correccion"],["autocorreccion"],
    "Pausa intermedia y autocorreccion en la misma frase.")
add(AC,"F","pago","Para Jose Luis no, para Maria Elena, dos mil bolivianos.","listo",
    {"persona":"Maria Elena","monto":"2000"},["correccion"],["negacion","persona"])

# -------------------------------------------------- G: no-habla y adversarial
add(AJ,"G","fuera_de_alcance","",'rechazado',{},["silencio_3s"],["no_habla"],
    "Tres segundos de silencio. Cualquier texto aceptado aqui es una falsa afirmacion.")
add(AJ,"G","fuera_de_alcance","",'rechazado',{},["ruido_viento"],["no_habla"])
add(AJ,"G","fuera_de_alcance","Paralelepipedo.","rechazado",{},[],["fuera_de_dominio"],
    "Palabra aislada sin relacion con el dominio. No debe producir un dato.")
add(AC,"G","fuera_de_alcance","",'rechazado',{},["silencio_10s"],["no_habla"])
add(AC,"G","fuera_de_alcance","",'rechazado',{},["silencio_30s"],["no_habla"],
    "Treinta segundos. Mide tambien si el motor se cuelga o suelta el microfono.")
add(AC,"G","fuera_de_alcance","",'rechazado',{},["ruido_tractor"],["no_habla"])
add(AC,"G","fuera_de_alcance","",'rechazado',{},["ruido_conversacion"],["no_habla"],
    "Conversacion de fondo: hay voz, pero no es la del operador.")
add(AC,"G","fuera_de_alcance","",'rechazado',{},["ruido_radio"],["no_habla"],
    "Musica. Es el caso que en la Fase 0 devolvio «[MUSICA]» como resultado valido.")
add(AC,"G","fuera_de_alcance","",'rechazado',{},["golpe_microfono"],["no_habla"])
add(AC,"G","fuera_de_alcance","Manana quizas llueva bastante por el norte.","rechazado",{},[],
    ["fuera_de_dominio"],"Habla real y bien formada, pero fuera del dominio.")

# ------------------------------------------- pausas largas y habla continuada
add(AC,"B","compra",
    "Compra de veinte litros de Bellator ...... y tambien quince kilos de Mancozeb.","listo",
    {"producto":"Bellator|Mancozeb","cantidad":"20|15"},["pausas"],["pausa_larga"],
    "Pausa de unos tres segundos en los puntos suspensivos: mide si el motor cierra el turno "
    "antes de tiempo y pierde la segunda mitad.")
add(AJ,"B","compra","Cuarenta litros de Glifosato ...... para el chaco Monte Verde.","listo",
    {"producto":"Glifosato","cantidad":"40","chaco":"Monte Verde"},["pausas"],["pausa_larga"])

# --------------------------------------------------------------------- salida
for i, s in enumerate(S):
    prefix = "HAJ" if s["split"] == AJ else "HAC"
    n = sum(1 for x in S[:i + 1] if x["split"] == s["split"])
    s["id"] = f"{prefix}-{n:03d}"

def norm(t):
    t = unicodedata.normalize("NFKD", t.lower())
    return "".join(c for c in t if not unicodedata.combining(c)).strip(" .,")

aj = {norm(s["text"]) for s in S if s["split"] == AJ and s["text"]}
ac = {norm(s["text"]) for s in S if s["split"] == AC and s["text"]}
shared = aj & ac
assert not shared, f"ajuste y aceptacion comparten frases: {shared}"

# Frases heredadas de la Fase 0: se permiten, pero SOLO en el mismo conjunto en
# el que ya estaban alli. Reutilizar en aceptacion algo con lo que ya se afino
# mediria el ajuste, no la capacidad del motor.
import os
phase0 = json.load(io.open("assets/corpus.json", encoding="utf-8"))["samples"]
old_by_text = {norm(x["text"]): x for x in phase0 if x["text"]}
for s in S:
    if not s["text"]:
        continue
    prev = old_by_text.get(norm(s["text"]))
    if prev is None:
        continue
    assert "heredada_fase0" in s["tags"], (
        f'{s["id"]} repite {prev["id"]} sin declararse heredada'
    )
    assert prev["split"] == s["split"], (
        f'{s["id"]} cambia de conjunto respecto de {prev["id"]}'
    )

cats = collections.Counter(s["category"] for s in S)
assert set(cats) == set("ABCDEFG"), cats
for split in (AJ, AC):
    present = {s["category"] for s in S if s["split"] == split}
    assert set("ABCDEFG") <= present, (split, present)

doc = {
    "schemaVersion": 2,
    "corpusVersion": "hybrid-1.0.0",
    "locale": "es-BO",
    "audio": "NINGUNO_GRABADO",
    "consentimiento": (
        "El corpus es texto. No contiene ni referencia grabaciones de personas reales. "
        "Personas, proveedores y chacos son ficticios."
    ),
    "relacionConFase0": (
        "Corpus SEPARADO de assets/corpus.json, que no se modifica. Aquel sigue siendo la "
        "referencia comparable con lo ya medido en el POCO; este anade las categorias A-G "
        "que pide EVOLUTION-3_HYBRID_ENGINE_BENCHMARK_PLAN.md. No comparten frases."
    ),
    "categorias": {
        "A": "Acciones cortas",
        "B": "Dictado largo de compras",
        "C": "Aplicaciones y planificacion",
        "D": "Pagos",
        "E": "Catalogo agricola",
        "F": "Negaciones y correcciones",
        "G": "No-habla y adversarial",
    },
    "counts": {
        "total": len(S),
        "ajuste": sum(1 for s in S if s["split"] == AJ),
        "aceptacion": sum(1 for s in S if s["split"] == AC),
        "porCategoria": dict(sorted(cats.items())),
        "porIntencion": dict(sorted(collections.Counter(s["intent"] for s in S).items())),
        "porResultadoEsperado": dict(
            sorted(collections.Counter(s["expected"] for s in S).items())
        ),
        "sinHabla": sum(1 for s in S if not s["text"]),
    },
    "samples": [
        {
            "id": s["id"], "split": s["split"], "category": s["category"],
            "intent": s["intent"], "text": s["text"], "expected": s["expected"],
            "slots": s["slots"], "conditions": s["conditions"], "tags": s["tags"],
            **({"note": s["note"]} if s["note"] else {}),
        }
        for s in S
    ],
}

out = "assets/corpus_hybrid.json"
io.open(out, "w", encoding="utf-8", newline="\n").write(
    json.dumps(doc, ensure_ascii=False, indent=2) + "\n"
)
print("escrito", out)
print("total", doc["counts"]["total"], "ajuste", doc["counts"]["ajuste"],
      "aceptacion", doc["counts"]["aceptacion"])
print("categorias", doc["counts"]["porCategoria"])
print("sin habla", doc["counts"]["sinHabla"])
