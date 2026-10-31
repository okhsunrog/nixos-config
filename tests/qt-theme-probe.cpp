#include <QApplication>
#include <QColor>
#include <QCoreApplication>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QPalette>
#include <QSaveFile>
#include <QProxyStyle>
#include <QStyleFactory>
#include <QTimer>
#include <QVariant>
#include <KColorScheme>
#include <iostream>

static bool check(bool condition, const char *message) {
    if (!condition) std::cerr << message << '\n';
    return condition;
}

int main(int argc, char **argv) {
    QApplication app(argc, argv);
    QCoreApplication::processEvents();
    const bool niri = app.arguments().value(1) == "niri";
    const auto scheme = app.property("KDE_COLOR_SCHEME_PATH").toString();
    const QColor expected = niri ? QColor(20, 30, 40) : QColor(230, 235, 240);
    const auto window = app.palette().color(QPalette::Window);
    const auto kdeWindow = KColorScheme(QPalette::Active, KColorScheme::Window).background().color();
    const auto proxy = qobject_cast<QProxyStyle *>(app.style());
    const auto baseStyle = proxy ? proxy->baseStyle()->objectName() : app.style()->objectName();
    std::cout << QJsonDocument(QJsonObject{
        {"qt", QT_VERSION_STR}, {"scheme", scheme},
        {"window", window.name()}, {"kdeWindow", kdeWindow.name()},
        {"style", app.style()->objectName()}, {"baseStyle", baseStyle}
    }).toJson(QJsonDocument::Compact).constData() << '\n';
    if (app.arguments().value(1) == "inspect") return 0;
    if (!check(niri ? !scheme.isEmpty() : scheme.isEmpty(), "Wrong platform theme isolation") ||
        !check(kdeWindow == expected, "KDE application palette did not follow selected desktop")) return 1;
    if (!niri) return 0;
    if (!check(window == expected, "Qt application palette did not follow Dux")) return 1;
    if (!check(baseStyle.compare("breeze", Qt::CaseInsensitive) == 0,
               "Breeze is unavailable; Qtengine fell back to a basic style")) return 1;

    // Dux writes its config atomically on theme changes. Verify already-running
    // Qt and KDE applications follow that change without editing kdeglobals.
    QTimer::singleShot(100, [&]() {
        QSaveFile config(qEnvironmentVariable("XDG_CONFIG_HOME") + "/qtengine/config.json");
        if (!config.open(QIODevice::WriteOnly)) { app.exit(2); return; }
        config.write(QJsonDocument(QJsonObject{{"theme", QJsonObject{
            {"colorScheme", qEnvironmentVariable("LIGHT_SCHEME")}, {"style", "Fusion"}
        }}}).toJson());
        if (!config.commit()) app.exit(2);
    });
    QTimer poll;
    QObject::connect(&poll, &QTimer::timeout, [&]() {
        if (app.palette().color(QPalette::Window) == QColor(230, 235, 240) &&
            KColorScheme(QPalette::Active, KColorScheme::Window).background().color() == QColor(230, 235, 240))
            app.exit(0);
    });
    poll.start(50);
    QTimer::singleShot(8000, [&]() { std::cerr << "Live theme update timed out\n"; app.exit(3); });
    return app.exec();
}
