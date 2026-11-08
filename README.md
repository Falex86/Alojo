# Ajoló

Ajoló es una mascota de píxeles para Apple Watch. El reloj conserva la partida. En ambos dispositivos puedes cuidar a la mascota, pesarla y jugar. El iPhone también permite configurar el ciclo, incubar huevos, ver el diario y conectar jugadores cercanos.

## Cuenta y guardado en Supabase

- Cada correo registrado en **Supabase Auth** tiene una sola partida activa. La cuenta conserva las generaciones de su ajolote y los nuevos linajes. Para crear la cuenta o iniciar sesión, abre **Cuenta** en el iPhone y mantén Ajoló abierto en su reloj emparejado. Si Supabase solicita confirmar el correo, introduce el código del mensaje en **Verify email**.
- El Apple Watch aplica los cuidados. Guarda una copia de trabajo y los cambios pendientes para que puedas jugar sin internet después de la primera sincronización. Intenta sincronizar al abrir y cada 60 segundos mientras la app sigue activa. Al reabrir, recupera el tiempo transcurrido y reintenta la subida. La app no programa sincronización en segundo plano.
- Supabase guarda la partida completa, incluido el diario, la despensa y el álbum. Para recuperar la partida en otro reloj, vincula el mismo correo desde el iPhone. Si dos relojes modifican la misma partida, el iPhone muestra **Choose a save** en **Setup** antes de sustituir alguna versión. El iPhone conserva una vista de la última copia recibida de su reloj.
- Los cuidados del iPhone viajan por Watch Connectivity cuando ambas apps están abiertas. Dos iPhone cercanos usan la red local para presentar sus ajolotes y confirmar una pareja. El inicio de sesión y la sincronización de la partida usan internet.
- Supabase restringe cada fila al propietario autenticado. El reloj guarda los tokens de sesión en el llavero. La contraseña se usa al iniciar sesión y no se guarda en la app. La configuración solo admite la clave **publishable** de Supabase.

### Configurar un proyecto Supabase propio

Este repositorio ya incluye la URL y la clave pública del proyecto de la organización **Ajoló**. El esquema de guardado y la validación de encuentros se aplicaron desde el editor SQL. Los siguientes pasos son para configurar otra instancia.

1. Crea un proyecto independiente y habilita el acceso con correo y contraseña en Authentication.
2. En **Authentication → Emails → Confirm sign up**, configura la plantilla para mostrar `{{ .Token }}` como código de confirmación.
3. Aplica la migración de `supabase/migrations` al proyecto de Ajoló.
4. Coloca la URL del proyecto y su clave **publishable** en `Shared/CloudConfiguration.plist`.
5. Compila las dos apps desde Xcode, abre ambas en dispositivos emparejados y vincula la cuenta desde el iPhone. El reloj habilita la incubación tras su primera conexión a Supabase.

Para enviar confirmaciones a correos ajenos a la organización, configura un proveedor de correo. El servicio de correo predeterminado de Supabase solo entrega mensajes a integrantes del equipo. [Configurar correo en Supabase](https://supabase.com/docs/guides/auth/auth-smtp)

## Pantallas del Apple Watch

- **Hábitat.** Al abrir Ajoló, el personaje ocupa el fondo de la pantalla con su nombre y día de vida. El estado cambia según lo que más necesita, como comida, descanso, baño, aseo o tratamiento. Los iconos aplican **Feed**, **Rest**, **Bath**, **Bathroom**, **Exercise**, **Weigh** y **Vaccine**. Puedes tocar un icono, o girar la Digital Crown para seleccionarlo y tocar **✓**. Cada acción completada tiene su animación. Si la acción todavía no se puede realizar, aparece el motivo.
- **Stats.** Desliza a la izquierda para ver comida, ánimo, energía, fuerza, peso, higiene, necesidad de ir al baño y riesgo de enfermedad. Desde aquí puedes abrir **Pantry** para dar los bocados que ganaste. Otro deslizamiento a la izquierda lleva a **Play**.
- **Reloj ambiental.** Desliza a la derecha desde el hábitat. Muestra la mascota, la hora, la fecha completa, el nombre y el día de vida. Es una pantalla de Ajoló sin controles ni animaciones de cuidado.

## Ajustes iniciales

En **Setup** del iPhone eliges **14, 30 o 60 días** para el ciclo, **15 minutos, 1 hora o 3 horas** para incubar y el estilo de pantalla del reloj. Puedes ajustarlos antes de iniciar el primer huevo o mientras sigue incubando. Si acortas la incubación por debajo del tiempo que ya pasó, el huevo eclosiona al guardar. Desde la primera eclosión, los ajustes se bloquean y se conservan para todos los descendientes y linajes nuevos de esa cuenta. En cada huevo nuevo puedes elegir el nombre y el sexo de esa mascota. Mantén Ajoló abierto en el Apple Watch para guardar ajustes o incubar desde el iPhone.

## Cuidados, higiene y báscula

Los siete controles rápidos están en el reloj. En el iPhone, **Habitat → Care & scale** ofrece los mismos cuidados y la báscula. Mantén ambas apps abiertas para aplicar un cuidado desde el iPhone. La báscula muestra gramos virtuales y el peso de referencia según la edad, especie, tamaño y complexión. El exceso de peso aumenta la lectura.

La limpieza empieza en 100 y baja **0,8 puntos por hora** después de la eclosión. La necesidad de ir al baño sube **4 puntos por hora**, más **8 por comida normal o nutritiva** y **12 por un bocado dulce**. Si llega a 100, la limpieza baja **2,2 puntos por hora**. Puedes llevar a la mascota al baño a partir de 15 puntos de necesidad. Eso vacía el indicador. El baño repone **70 puntos de limpieza**, hasta 100. La falta de limpieza puede añadir hasta **10 puntos porcentuales** al riesgo diario de enfermarse.

## Vida, tiempo y diario

| Hito | Ciclo de 14 días | Ciclo de 30 días | Ciclo de 60 días |
| --- | ---: | ---: | ---: |
| Eclosión | 15 min, 1 h o 3 h | 15 min, 1 h o 3 h | 15 min, 1 h o 3 h |
| Empieza la etapa joven | Día 1 | Día 2 | Día 4 |
| Empieza la adultez | Día 3 | Día 7 | Día 14 |
| Último día para criar | Día 10 | Día 23 | Día 47 |
| Empieza la vejez | Día 11 | Día 24 | Día 48 |
| Muere de vejez | Día 14 | Día 30 | Día 60 |

La edad se cuenta desde que empieza la incubación. Los cuidados y los juegos se habilitan después de la eclosión.
- La edad avanza en periodos reales de 24 horas. El reloj recalcula el tiempo transcurrido al abrir la app y actualiza el hábitat mientras está visible. La simulación queda suspendida en segundo plano.
- Es de noche entre las 20:00 y las 07:00 según la zona local del reloj. Viajar cambia el día y la noche del hábitat sin alterar la edad acumulada.
- Cada cuidado conserva la zona horaria y el desplazamiento UTC del momento en que se registró. Para hitos calculados tras una ausencia, la app usa la última zona que conocía.
- El diario del reloj conserva hitos, enfermedad, recuperación y los últimos 120 cuidados por vida. El iPhone muestra el diario de la vida actual y un resumen de las últimas ocho generaciones anteriores.
- Cada vida empieza con 95 de comida, ánimo y energía y cero exceso de peso. La fuerza inicial es 45 en un linaje nuevo, o entre 40 y 50 si se hereda. Las barras van de 0 a 100. Tras eclosionar, el ánimo baja 0,9 puntos por hora, la energía 1,4 y la fuerza 0,4, hasta llegar a cero. La energía solo baja mientras está despierto.

## Comida, fuerza y peso

| Opción | Efecto |
| --- | --- |
| Comer | Sube la comida 52 puntos. La ración normal está disponible en el hábitat. |
| Bocado nutritivo | Consume una unidad de la despensa y sube la comida 60 puntos. |
| Bocado chatarra | Consume una unidad de la despensa, sube la comida 70 puntos, el ánimo 8 y el exceso de peso 12. |
| Lagartijas · Push-ups | Fuerza +18, energía −12, comida −6 y exceso de peso −4. |
| Correr · Run | Fuerza +12, energía −14, comida −8 y exceso de peso −8. |
| Nadar · Swim | Fuerza +15, energía −10, comida −6 y exceso de peso −6. |

- Cuanta más fuerza tenga el ajolote, más rápido consume comida. En cada momento consume entre 1,65 y 2,55 puntos por hora, según la fuerza que tenga. El consumo baja gradualmente si la fuerza disminuye.
- La chatarra se puede guardar. El efecto sobre el peso aparece al comerla. A partir de 36 puntos de exceso de peso, su silueta se ensancha. El exceso de peso baja 0,35 puntos por hora y baja más rápido con ejercicio.
- Los tres ejercicios comparten una pausa de doce horas. La mascota debe estar despierta y sana, con al menos 30 puntos de energía y 25 de comida. Cada ejercicio tiene su propia animación.
- Tras **72 horas consecutivas con la barra de comida vacía**, el ajolote muere por hambre. Cualquier ración que coma antes de ese límite interrumpe la racha de hambre.

## Enfermedad y vacuna

- Cada 24 horas de vida, si está sano y sin protección, existe una posibilidad de que contraiga **fiebre de burbujas**, una enfermedad ficticia. Reabrir la app no repite el sorteo del día.
- El riesgo va de **5 % a 20 %** según la fuerza. El exceso de peso puede sumar hasta **15 puntos porcentuales**.
- Una fiebre nueva es fatal si pasan **72 horas sin tratamiento**. Vacunar antes del plazo inicia una recuperación de **una hora**. Las fiebres guardadas en versiones anteriores conservan su recuperación programada.
- La vacuna preventiva protege durante 48 horas y se puede aplicar cada 96 horas. El tratamiento está disponible aunque esté pendiente ese intervalo, incluso mientras la mascota duerme. Durante la fiebre, los juegos y el ejercicio quedan pausados.

## Sueño y caricias

- **Rest** pone a la mascota a dormir. Duerme **ocho horas reales seguidas** y despierta automáticamente, recuperando hasta **60 puntos de energía**. El hambre y el ciclo de vida siguen avanzando. El reloj recalcula el sueño al abrir la app.
- Pasadas **24 horas desde la eclosión o el último sueño completo**, se vuelve muy irritable. Solo se recupera con ocho horas seguidas. **Wake early** permite despertarla para darle otros cuidados, pero no reinicia el plazo ni concede energía.
- Si pasan **cinco días sin completar el sueño**, puede morir de agotamiento. La sesión de ocho horas debe terminar antes de que se cumpla el plazo o justo al llegar a él. El reloj usa el primer plazo fatal que se cumpla entre hambre, enfermedad, desvelo y vejez.
- Para acariciarla, toca al personaje despierto en el hábitat del reloj y mueve suavemente la muñeca de ida y vuelta. El reloj escucha el gesto durante seis segundos. Una caricia reconocida muestra corazones y suma hasta **8 puntos de ánimo**, con un premio cada diez minutos. Los datos del sensor se usan para reconocer el gesto en el reloj.

## Tres minijuegos

| Juego | Qué haces |
| --- | --- |
| Bubbles | Revienta burbujas numeradas siguiendo patrones ascendentes, descendentes y alternados. |
| Echoes | Memoriza secuencias de tres a cinco símbolos. Si te equivocas, puedes volver a mirar. |
| Shells | Usa pistas de distancia para encontrar tres conchas con intentos limitados por ronda. En el reloj también puedes seleccionar con la Digital Crown. |

Los tres juegos tienen tres rondas sin cronómetro. Se desbloquean cuando el ajolote nace y se pausan si está enfermo o dormido. Al terminar puedes ganar hasta **18 puntos de ánimo**, con un premio cada 30 minutos. En los primeros dos premios de cada día de vida eliges **un bocado nutritivo o uno chatarra** para la despensa. Puedes jugar desde **Play** en el iPhone con el reloj cerrado. El iPhone conserva un premio pendiente por mascota y el reloj lo aplica al abrir Ajoló. Los dos dispositivos pueden abrirse en momentos distintos.

## Especies, crianza y Ripple Duel

- En **Setup** del iPhone se elige **Male** o **Female** antes de incubar. Una mascota anterior sin sexo asignado se puede configurar una vez sin reiniciar su vida. Cada huevo de un linaje nuevo recibe una especie aleatoria entre ajolote, tortuga, pez globo y caballito de mar. Cada especie tiene su propia silueta, paleta en modo Color y peso de referencia. El tamaño y la complexión también se sortean. Los descendientes heredan la especie de uno de sus progenitores.
- En **Meet**, dos iPhone cercanos se encuentran por red local. Abre Ajoló en ambos teléfonos y sus relojes, acepta la invitación y pulsa **Introduce my pet** en ambos iPhone. Supabase valida la partida y el consentimiento de cada cuenta.
- Un macho y una hembra adultos elegibles pueden criar una vez. Si ambos aceptan, cada reloj obtiene un huevo hermano. Supabase impide repetir la crianza con la misma mascota y bloquea parejas de familiares directos y hermanos. Dos hembras pueden conocerse sin iniciar crianza ni duelo.
- Dos machos sanos que ya nacieron pueden jugar **Ripple Duel**. Cada jugador elige tres movimientos en secreto. **Dash** vence a **Splash**, **Splash** vence a **Guard** y **Guard** vence a **Dash**. Supabase puntúa cada ronda y devuelve un resultado compartido. El duelo no causa daño ni cambia las estadísticas.
- Mantén Ajoló abierto en los relojes para enviar las elecciones y recibir el resultado. Los encuentros requieren internet. Los cuidados y juegos individuales conservan el modo sin conexión.

El álbum conserva retratos, progenitores, edad, causa de muerte y totales de juegos y entrenamientos. El primer encuentro con descendencia desbloquea un marco. La tercera generación añade coral al hábitat.

## Pantalla e instalación

**Auto** usa verde LCD en Series 7 y color con animación y más detalles en Series 9. Puedes elegir **Auto**, **Classic** o **Color** en **Setup → Watch display** del iPhone antes de la primera eclosión. La animación respeta la opción Reducir movimiento.

1. Abre `Ajolo.xcodeproj`. La app requiere iOS 16 o posterior y watchOS 9.2 o posterior.
2. En **Signing & Capabilities**, selecciona tu equipo de Apple para **Ajolo** y **AjoloWatch**. Si cambias los identificadores de paquete, actualiza también `WKCompanionAppBundleIdentifier` del reloj para que coincida con el del iPhone.
3. Ejecuta **Ajolo** en el iPhone y **AjoloWatch** en el reloj emparejado.
4. Con Ajoló abierto en el reloj, entra en **Setup → Start incubation** desde el iPhone.

## Apple Health en iPhone

En Xcode, selecciona el destino iPhone **Ajolo → Signing & Capabilities** y añade **HealthKit** con un equipo de firma compatible. La compilación normal de Ajoló funciona sin ese permiso. Reinstala la app de iPhone y usa **Account → Apple Health → Connect Apple Health** para elegir los datos que quieres compartir.

Con Ajoló abierto en el iPhone, la mascota nada con más energía al detectar minutos de ejercicio recientes que ya llegaron a Apple Health. Un entrenamiento completado de al menos diez minutos durante la sesión de iPhone puede poner en cola un ejercicio para la mascota. El reloj aplica las reglas habituales de ejercicio al recibirlo. Ajoló no tiene acceso a un entrenamiento en vivo de otra app.

En iOS 18 o posterior, una entrada reciente de **State of Mind** con la etiqueta **Stressed** muestra una reacción tranquila en el hábitat del iPhone. Es una reacción al estado que registraste y no modifica las estadísticas de la mascota. Ajoló no guarda muestras ni entradas de salud en Supabase y solo las consulta mientras la app de iPhone está activa.
