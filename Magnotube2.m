close all;
clear all;
clc;
s = serialport("COM5", 1500000, "Timeout", 3, "ByteOrder", "little-endian");
configureTerminator(s, "CR/LF");
pause(2);
flush(s);

%Alarmsound preparation
[audioData, Fs] = audioread('Alarmsound.mp3');
player = audioplayer(audioData,Fs);

%Counter = Amount of measurements for debugging purposes
counter=0;
% Grid for 2D quiver plot
[I, J] = ndgrid(1:8, 1:8);

% Grid for 3D quiver plot
[L, M, N] = ndgrid(1:8, 1:8, 1);

% Grid for surface plot
interpolating_factor = 5;
[Xg, Yg] = meshgrid(1:8);
[Xq, Yq] = meshgrid(1:1/interpolating_factor:8);

% Window Settings
screen_size = get(0, 'ScreenSize');
screen_height = screen_size(3);
screen_width = screen_size(2);

window_width = screen_height / 2;
window_height = screen_height / 2.22;
window_x_pos = 1000;
window_y_pos = 100;

fig = figure('Position', [window_x_pos window_y_pos window_width window_height]);

% Preparations for plots
% 2D quiver plot XY
subplot(2,2,1);
q1 = quiver(J, I, zeros(8), zeros(8));
axis equal tight
xlim([0.5, 8.5]);
ylim([0.5, 8.5]);
xlabel('y');
ylabel('x');
title('Magnetfeldrichtung (X-Y-Ebene)');


% 2D surface plot XYZ
ax = subplot(2,2,2);
q6 = surf(Xg, Yg, zeros(8), 'EdgeColor', 'none');
hold on
axis auto
q61 = scatter3(0, 0, 0, 50, 'r', 'filled');
hold off
xlim([0.5, 8.5]); ylim([0.5, 8.5]); zlim([-0.5, 10000.5]);
xlabel('y');
ylabel('x');
zlabel('z');
shading interp;
view(2);
grid on
title('Absolute Strength');

axTrachea = subplot(2,2,[3 4]);
img = imread('TracheaV2.jpeg');
img = rot90(img, 1);
imshow(img);

axis image
axis on
hold on

img_size = size(img);
xlim([0 img_size(2)])
ylim([0 img_size(1)])
set(gca, 'YDir','reverse');
title('Position des Tubus in der Trachea')


% Startposition im Tracheabild
startX = 753;
startY = 753;

%--- Kalibrierung und Mapping Vorbereitungen---
%Startposition vorerst
calibrated = false;
O_TE_ref = [NaN NaN NaN]; %vorher Magnetfeldmaximum gespeichert, jetzt die berechneten Positionen xyz

imageCenterX = startX;
imageCenterY = startY;

scale_x = 60;
scale_y = 60;

px_plot = startX;
py_plot = startY;
% Punkt für Magnetmaximum im Tracheaplot px und py getauscht für Korrekte
% darstellung
h_point = plot(px_plot, py_plot, 'o', 'MarkerSize', 8, 'LineWidth', 2, 'MarkerEdgeColor', 'k', 'MarkerFaceColor', 'k');
% Persistence: letzte 30 gueltige Positionen anzeigen
traillength = 30;
trailPx = nan(1, traillength);
trailPy = nan(1, traillength);

% Duenne blaue Linie mit kleinen Spurpunkten
h_trail = plot(nan, nan, '.-', ...
    'Color', [0 0.45 0.9], ...
    'LineWidth', 1.5, ...
    'MarkerSize', 14);
% Alarm-Kreis
theta = linspace(0,2*pi,50);
r = 160; % Erlaubter Radius in Pixeln
h_circle = fill( ...
    px_plot + r*cos(theta), ...
    py_plot + r*sin(theta), ...
    [1 0 1], ... % grün
    'FaceAlpha',0.5, ...
    'EdgeColor','none');



b1 = uicontrol(fig, 'Style', 'togglebutton', 'String', 'Magnetic Reset');
b1.Position = [window_width/2-430 10 200 25];
b2 = uicontrol(fig, 'Style', 'togglebutton', 'String', 'Zero');
b2.Position = [window_width/2-210 10 200 25];
b3 = uicontrol(fig, 'Style', 'togglebutton', 'String', 'Magnetic Reset & Zero');
b3.Position = [window_width/2+10 10 200 25];
b4 = uicontrol(fig, 'Style', 'togglebutton', 'String', 'Set Reference');
b4.Position = [window_width/2+230 10 200 25];
b5 = uicontrol(fig, 'Style', 'togglebutton', 'String', 'Persistence');
b5.Position = [window_width/2+450 10 160 25];

% --- Initialisierung Gerät ---
writeline(s, "format bin");
ack = readline(s);
disp("ACK format bin: " + strtrim(ack));

writeline(s, "averaging 8");
ack = readline(s);
disp("ACK averaging 8: " + strtrim(ack));

flush(s);

% Get reference
writeline(s, "measurement auto");
while s.NumBytesAvailable < 1024
    pause(0.1);
end

data = read(s, 256, "single");  % 64 Sensoren * 4 Werte = 256 singles
data_matrix = reshape(data, 4, 64);

ack = readline(s);
disp("ACK measurement auto: " + strtrim(ack));
if ~strcmp(strtrim(ack), "Done")
    error("Protocol error after measurement auto. ACK = '%s'", strtrim(ack));
end

vx_ref = data_matrix(1, :);
vy_ref = data_matrix(2, :);
vz_ref = data_matrix(3, :);

%c_point = zeros(8); Kann raus?
freq = zeros(50,1);
also_zero = false;

while(1)

   tic;
%pause(0.25);


    if (b1.Value == true || b3.Value == true) % Magnetic Reset
        if (b3.Value == true)
            also_zero = true;
        end

        writeline(s, "reset");
        ack = readline(s);
        disp("ACK reset: " + strtrim(ack));

        if strcmp(strtrim(ack), "Done")
            fprintf("Magnetic reset successful\n");
        else
            fprintf("Error during magnetic reset: %s\n", strtrim(ack));
            break;
        end

        flush(s);

        if (b1.Value == true)
            b1.Value = false;
        end
    end


    % Daten anfordern
 % pause(0.1);
    writeline(s, "measurement read 0-63");

    expectedBytes = 256 * 4;  % 256 single-Werte mit je 4 Bytes
    timeout = 1;              % Sekunden
    timedOut = false;         % timedOut flag
    t_receive = tic;

    %Daten einlesen
    while s.NumBytesAvailable < expectedBytes + 6
        if toc(t_receive) >= timeout
            fprintf("\n--- Empfangsdiagnose ---\n");
            fprintf("Zeit: %.3f s\n", toc(t_receive));
            fprintf("Bytes im Puffer: %d\n", s.NumBytesAvailable);

            % Bereits vorhandene Bytes sichern
            n = s.NumBytesAvailable;
            if n > 0
                raw = read(s, n, "uint8");
                fprintf("Erste Bytes (hex): ");
                fprintf("%02X ", raw(1:min(20, numel(raw))));
                fprintf("\n");
            end

            warning("Messdaten unvollständig empfangen.");
            %Reset ausführen
            writeline(s, "reset");
            ack = readline(s);
            disp("ACK reset: " + strtrim(ack));

            if strcmp(strtrim(ack), "Done")
                fprintf("Magnetic reset successful\n");
            else
                fprintf("Error during magnetic reset: %s\n", strtrim(ack));
                break;
            end
            flush(s);
            timedOut = true;
            break;
        end

        pause(0.05);
    end

    if timedOut
        continue;
    end
    bytesBeforeRead = s.NumBytesAvailable;
    fprintf("Bytes vor dem Lesen: %d\n", bytesBeforeRead);

    % Genau 256 single-Werte einlesen
    data = read(s, 256, "single");

    fprintf("Messwerte eingelesen: %d\n", numel(data));

    % Abschlussbestätigung lesen
    ack = strtrim(readline(s));
    disp("ACK measurement read: " + ack);

    if ~strcmp(ack, "Done")
        error("Protocol error after measurement read. ACK = '%s'", ack);
    end

    % Nächste Messung starten
    writeline(s, "measurement start 0-63");
    ack = strtrim(readline(s));
    disp("ACK measurement start: " + ack);

    if ~strcmp(ack, "Done")
        error("Protocol error after measurement start. ACK = '%s'", ack);
    end

    % Daten umformatieren
    data_matrix = reshape(data, 4, 64);

    if (b2.Value == true || also_zero == true) % Zero
        calibrated = false;
        vx_ref = data_matrix(1, :);
        vy_ref = data_matrix(2, :);
        vz_ref = data_matrix(3, :);

        if (b2.Value == true)
            b2.Value = false;
        end
        if (also_zero == true)
            b3.Value = false;
            also_zero = false;
        end
    end

    vx = data_matrix(1, :) - vx_ref;
    vy = data_matrix(2, :) - vy_ref;
    vz = data_matrix(3, :) - vz_ref;


    counter = counter + 1; % zählt jede eingelesene Messung, 
% um die erste Ortungsberechnung zu erkennen und die xyz regelmäßig
% auszugeben

    % In 8×8 Matrizen umformen
    X = fliplr(reshape(vx, 8, 8)).';
    Y = fliplr(reshape(vy, 8, 8)).';
    Z = fliplr(reshape(-vz, 8, 8)).';

    % --- Neue 3D-Positionsbestimmung mit Ortung_TE ---
    %Magnetfeldwerte aller 64 Sensoren mit BxByBz
    % 64 Sensoren mit jeweils Bx, By, Bz
    % Testannahme: Messwerte liegen in Mikrotesla vor
    B_mess = [reshape(X.', 64, 1), ...
        reshape(Y.', 64, 1), ...
        reshape(Z.', 64, 1)] * 1e-6; 

    % Die Ortung funktion so oft aufrufen, um die Positionsschätzung zu optimieren
    % Mehrere TE-Optimierungsschritte pro Messung
    %O_TE = xyz in mm, 
    for schritt = 1:500
      [O_TE, ~, fehler_TE, ~] = Ortung_TE( ...
           B_mess, false);
    end
%[O_TE, ~, fehler_TE, ~] = Ortung_TE( ...
        %   B_mess, counter ==1);
%[O_TE, ~, fehler_TE, ~] = Ortung_TE(  B_mess, false);
    % Pruefen, ob die TE-Ortung brauchbar(logisch) ist
    feld_RMS_TE = sqrt(mean(B_mess(:).^2));

    TE_ok = feld_RMS_TE > 1e-7 && ...
       all(isfinite(O_TE)) && ...
        fehler_TE < 0.10 * feld_RMS_TE;
%TE_ok =1;
    % XYZ-Ergebnis alle 10 Messungen ausgeben
    if mod(counter, 10) == 0
        fprintf('TE-Ortung: X = %.2f mm, Y = %.2f mm, Z = %.2f mm, RMS = %.2f uT\n', ...
            O_TE(1), O_TE(2), O_TE(3), fehler_TE * 1e6);
    end
    % Betrag errechnen
    V = sqrt(X.^2 + Y.^2 + Z.^2);
    Vq = interp2(Xg, Yg, V, Xq, Yq, 'cubic');
    % TE-Position als Referenz speichern, beim drücken set correlation wird
    % die berechnete 3D Position gespeichert, statt der Ort des
    % Magnetfeldmaximums
    if b4.Value == true

        if TE_ok
            O_TE_ref = O_TE;
            calibrated = true;
            disp('3D-Referenzposition gespeichert.');
        else
          disp('TE-Ortung unzuverlaessig. Referenz nicht gesetzt.');
        end

        b4.Value = false;
disp('b4 false')
    end

    % Maximum
    [maxValue, maxIndex] = max(Vq(:));
    [maxY, maxX] = ind2sub(size(Vq), maxIndex);
    maxX = maxX / interpolating_factor + (interpolating_factor - 1) / interpolating_factor;
    maxY = maxY / interpolating_factor + (interpolating_factor - 1) / interpolating_factor;
disp (calibrated);
disp(TE_ok);
  % TE-Position auf das Tracheabild uebertragen
if ~calibrated
    px_plot = imageCenterX;
    py_plot = imageCenterY;

elseif TE_ok
    dx = O_TE(1) - O_TE_ref(1);
    dy = O_TE(2) - O_TE_ref(2);

    px_plot = imageCenterX + (scale_x / 6.3) * dy;
    py_plot = imageCenterY - (scale_y / 6.3) * dx;
end


    %Alarmsystemberechnung
    dist = sqrt((px_plot - imageCenterX)^2 +(py_plot - imageCenterY)^2);
    alarm = calibrated && TE_ok && dist > r;
    % Vector data aktualisieren
    set(q1, 'UData', Y, 'VData', X);
    set(q6, 'XData', Xq, 'YData', Yq, 'ZData', Vq);
    set(q61, 'XData', maxX, 'YData', maxY, 'ZData', maxValue);
    %aktualsiere Magnetmaximumpunkt im Plot
    set(h_point,'XData', px_plot, 'YData', py_plot);
   hTitle = title(axTrachea, { ...
    'Position des Tubus in der Trachea', ...
    sprintf('3D-Ortung: X = %.1f | Y = %.1f | Z = %.1f mm', ...
    O_TE(1), O_TE(2), O_TE(3)) ...
});

hTitle.Units = 'normalized';
hTitle.Position = [0.5, 1.08, 0];
   if b5.Value == 1
    b5.String = 'Persistence: On';

    % Nur gueltige Magnetpositionen zur Spur hinzufuegen
    if calibrated && TE_ok
        trailPx = [trailPx(2:end), px_plot];
        trailPy = [trailPy(2:end), py_plot];
    end

    % Bewegungsspur aktualisieren
    set(h_trail, ...
        'XData', trailPx, ...
        'YData', trailPy);
    else
    b5.String = 'Persistence: Off';

    % Spur ausblenden
    set(h_trail, ...
        'XData', nan(1, traillength), ...
        'YData', nan(1, traillength));

    % Gespeicherte Spur zuruecksetzen
    trailPx = nan(1, traillength);
    trailPy = nan(1, traillength);
end


    drawnow limitrate;

    freq = circshift(freq, 1);
    freq(1) = 1 / toc;
    fprintf('Frequency: %f Hz\n', mean(freq));

    %Alarmsystem aktion
    if alarm

        %Ortung gültig, schwarzer Punkt außerhalb des Kreises.
        set(h_circle, 'FaceColor', 'r');
        % FOR DEBUGGING set(h_point, 'Color', 'r', 'MarkerSize', 15);
        % Nur starten wenn:
        % 1. Alarm gerade neu ist
        % 2. Kein Sound läuft
        if alarm && strcmp(player.Running, 'off')
            play(player);
        end


    else
    if calibrated && ~TE_ok
        % Orange: Magnetposition nicht zuverlässig, Ortung ungültig, tatsächliche Position unbekannt.
        set(h_circle, 'FaceColor', [1 0.6 0]);
    else
        % Gruen: Ortung gültig, schwarzer Punkt innerhalb des Kreises.
        set(h_circle, 'FaceColor', [0 1 0]);
    end

    if strcmp(player.Running, 'on')
        stop(player);
    end
end
end
