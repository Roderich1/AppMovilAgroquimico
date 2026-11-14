"""Pruebas de f09_metricas.py con DATOS SINTÉTICOS (no son mediciones).

    python -I -B -m unittest discover -s docs/f09/evaluacion/metricas -p "test_*.py"
"""

import os
import sys
import unittest

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)

import f09_metricas as m  # noqa: E402

SINTETICOS = os.path.join(AQUI, "datos_sinteticos", "tomas_SINTETICAS.csv")
PLANTILLA = os.path.join(AQUI, "..", "registro_tomas_PLANTILLA.csv")


def _leer(ruta):
    with open(ruta, encoding="utf-8") as fh:
        return m.leer_registro(fh.read())


class DatosSinteticos(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.r = m.calcular(_leer(SINTETICOS))
        cls.g = cls.r["grupos"][0]

    def test_un_solo_grupo_por_telefono_condicion_y_motor(self):
        self.assertEqual(len(self.r["grupos"]), 1)
        self.assertEqual(
            (self.g["telefono"], self.g["condicion"], self.g["motor"]),
            ("TEL-SINTETICO-A", "tranquilo", "local"),
        )
        self.assertEqual(self.g["fichas"], 4)
        self.assertEqual(self.g["dictados"], 4)

    def test_condicion_sin_tomas_es_not_run(self):
        self.assertEqual(
            self.r["no_ejecutado"],
            [{"telefono": "TEL-SINTETICO-A", "condicion": "ruido", "motor": "local", "estado": "NOT_RUN"}],
        )

    def test_d1_por_tipo_con_numerador_y_denominador(self):
        c = self.g["d1_campos_correctos"]
        self.assertEqual((c["producto"]["numerador"], c["producto"]["denominador"]), (3, 4))
        self.assertEqual(c["producto"]["veredicto"], m.NO_CUMPLE)
        self.assertEqual((c["cantidad"]["numerador"], c["cantidad"]["denominador"]), (2, 4))
        self.assertEqual((c["unidad"]["numerador"], c["unidad"]["denominador"]), (3, 4))
        # Sólo una ficha esperaba parcela o persona.
        self.assertEqual((c["parcela_o_persona"]["numerador"], c["parcela_o_persona"]["denominador"]), (1, 1))
        self.assertEqual(c["parcela_o_persona"]["veredicto"], m.CUMPLE)
        self.assertEqual(c["producto"]["umbral_pct"], 90)

    def test_d1_errores_separados_por_causa(self):
        c = self.g["d1_campos_correctos"]
        self.assertEqual(c["cantidad"]["errores_por_causa"]["interpretacion"], 1)
        self.assertEqual(c["cantidad"]["errores_por_causa"]["transcripcion"], 1)
        self.assertEqual(c["producto"]["errores_por_causa"]["transcripcion"], 1)

    def test_d1_campos_indebidos_aparte(self):
        self.assertEqual(self.g["d1_campos_indebidos"], {"conteo": 1, "dictados_afectados": 1})

    def test_d2_incluye_los_fallidos_en_el_denominador(self):
        d2 = self.g["d2_transcripciones_utiles"]
        self.assertEqual((d2["numerador"], d2["denominador"]), (2, 4))
        self.assertEqual(d2["veredicto"], m.NO_CUMPLE)

    def test_percentiles_por_rango_mas_cercano(self):
        pp = self.g["primer_parcial_ms"]
        self.assertEqual((pp["n"], pp["p50"], pp["p95"]), (3, 700, 900))
        self.assertEqual(pp["veredicto"], m.CUMPLE)
        fin = self.g["final_segunda_pasada_ms"]
        # La frase de 25 s queda fuera (frases de hasta 20 s).
        self.assertEqual((fin["n"], fin["p50"], fin["p95"]), (2, 2000, 2600))
        self.assertEqual(fin["veredicto"], m.CUMPLE)
        rtf = self.g["rtf_segunda_pasada"]
        self.assertEqual((rtf["n"], rtf["p95"]), (3, 0.52))
        self.assertEqual(rtf["veredicto"], m.NO_CUMPLE)

    def test_rechazo_fuera_de_los_denominadores(self):
        r = self.r["rechazo"]["TEL-SINTETICO-A"]
        self.assertEqual((r["muestras"], r["texto_aceptado"]), (3, 1))
        self.assertEqual(r["veredicto"], m.NO_CUMPLE)

    def test_escrituras_sin_confirmacion_y_lo_no_medido(self):
        e = self.r["escrituras_sin_confirmacion"]
        self.assertEqual(e["HOST"]["veredicto"], m.CUMPLE)
        self.assertEqual(e["TEL-SINTETICO-A"]["veredicto"], m.NOT_MEASURED)

    def test_sin_los_mismos_audios_la_comparacion_no_se_demuestra(self):
        comp = self.r["frente_a_android"]
        self.assertEqual(comp[0]["veredicto"], m.NO_DEMOSTRADO)

    def test_lo_de_sesion_no_lo_calcula(self):
        self.assertEqual(len(self.r["fuera_del_alcance_de_este_script"]), 4)


class Reglas(unittest.TestCase):
    def fila(self, **kw):
        base = {c: "" for c in _leer_cabecera()}
        base.update(
            toma_id="X", telefono="TEL-SINT", condicion="tranquilo", motor="local",
            ficha_id="F", estado_motor="ok",
        )
        base.update(kw)
        return base

    def test_sin_datos_todo_es_not_measured_nunca_cero(self):
        g = m.metricas_voz(m.Grupo("TEL-SINT", "tranquilo", "local", [self.fila()]))
        self.assertEqual(g["primer_parcial_ms"]["p50"], m.NOT_MEASURED)
        self.assertEqual(g["primer_parcial_ms"]["veredicto"], m.NOT_MEASURED)
        self.assertEqual(g["d1_campos_correctos"]["producto"]["veredicto"], m.NOT_MEASURED)
        self.assertEqual(g["rtf_segunda_pasada"]["p95"], m.NOT_MEASURED)

    def test_umbral_exacto_cumple_con_aritmetica_entera(self):
        filas = [self.fila(toma_id=str(i), ficha_id=str(i), campo_producto="correcto") for i in range(9)]
        filas.append(self.fila(toma_id="9", ficha_id="9", campo_producto="incorrecto"))
        g = m.metricas_voz(m.Grupo("TEL-SINT", "tranquilo", "local", filas))
        self.assertEqual(g["d1_campos_correctos"]["producto"]["veredicto"], m.CUMPLE)
        g = m.metricas_voz(m.Grupo("TEL-SINT", "ruido", "local", filas[1:]))
        # 8/9 = 88,9 % >= 80 % con ruido.
        self.assertEqual(g["d1_campos_correctos"]["producto"]["veredicto"], m.CUMPLE)

    def test_mismos_audios_permite_comparar_con_android(self):
        filas = [
            self.fila(toma_id="L1", audio_id="A1", campo_cantidad="correcto", campo_unidad="correcto"),
            self.fila(toma_id="A1", motor="android", audio_id="A1", campo_cantidad="incorrecto", campo_unidad="correcto"),
        ]
        comp = m.frente_a_android(filas)
        self.assertEqual(comp[0]["local"], {"numerador": 2, "denominador": 2})
        self.assertEqual(comp[0]["android"], {"numerador": 1, "denominador": 2})
        self.assertEqual(comp[0]["veredicto"], m.CUMPLE)

    def test_valores_y_condiciones_desconocidos_se_rechazan(self):
        with self.assertRaises(m.RegistroInvalido):
            m.leer_registro("toma_id,telefono,condicion,motor,ficha_id,estado_motor,campo_producto\nX,T,tranquilo,local,F,ok,casi\n")
        with self.assertRaises(m.RegistroInvalido):
            m.calcular([self.fila(condicion="exterior")])
        with self.assertRaises(m.RegistroInvalido):
            m.leer_registro("toma_id,telefono\nX,T\n")

    def test_la_plantilla_y_los_sinteticos_tienen_las_mismas_columnas(self):
        with open(SINTETICOS, encoding="utf-8") as fh:
            cabecera = [l for l in fh.read().splitlines() if not l.startswith("#")][0]
        self.assertEqual(cabecera.split(","), _leer_cabecera())

    def test_umbrales_copiados_de_c12(self):
        self.assertEqual(m.UMBRALES["campos_correctos_pct"], {"tranquilo": 90, "ruido": 80})
        self.assertEqual(m.UMBRALES["transcripciones_utiles_pct"], {"tranquilo": 80, "ruido": 70})
        self.assertEqual(m.UMBRALES["primer_parcial_ms"], {"p50": 800, "p95": 1500})
        self.assertEqual(m.UMBRALES["final_segunda_pasada_ms"]["p50"], 2500)
        self.assertEqual(m.UMBRALES["final_segunda_pasada_ms"]["p95"], 5000)
        self.assertEqual(m.UMBRALES["rtf_segunda_pasada"]["p95"], 0.50)


def _leer_cabecera():
    with open(PLANTILLA, encoding="utf-8") as fh:
        return fh.readline().strip().split(",")


if __name__ == "__main__":
    unittest.main()
