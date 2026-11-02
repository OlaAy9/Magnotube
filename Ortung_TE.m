function [O, M, fehler, B_hyp] = Ortung_TE(B_mess, reset)
  % ORTUNG_TE Ein zufaelliger Versuch pro Aufruf, Zustand persistent.
  % [O,M,fehler,B_hyp] = Ortung_TE(B_mess [,reset])
  % B_mess: 64x3 [Bx By Bz] in Tesla, Sensorreihenfolge wie unten.
  % O: 1x3 Position in mm; M: 1x3 Dipolmoment in A*m^2.
  % fehler: RMS aller 192 Feldkomponenten in Tesla.
  % reset=true setzt die interne Hypothese vor diesem Schritt zurueck.
  % Bei neuen Messdaten wird der bisherige Zustand als Startwert verwendet.
  % Modell: Punktdipol, kein Hintergrundfeld, Magnet oberhalb des Arrays.
  % Falls M eine Magnetisierung in A/m bezeichnet: Dipolmoment = M * Volumen.

  persistent p schritt_max;
  if nargin < 2
    reset = false;
  end
  % Test gegen fehlereingabe
  if ~isnumeric(B_mess) || ~isreal(B_mess) || ...
      ~isequal(size(B_mess), [64, 3]) || any(~isfinite(B_mess(:)))
    error('Ortung_TE: B_mess muss eine endliche reelle 64x3-Matrix sein.');
  end

  abstand = 6.3;                  % abstand der Sensor im Array mm prüfen !!!!
  moment_skala = 0.4;             % A*m^2, typisch fuer 3 g NdFeB ( ??) Den ;Magent wiegen !
                                  % Hier sollte vorsichtig PROBIERT WERDEN 0.38 0.35  pder in der anderen Richtung  
  % Lage der Sensoren auf der Platne 
  [sx, sy] = meshgrid((-3.5:3.5) * abstand);
  sensoren = [sx(:), sy(:), zeros(64, 1)];
  if isempty(p) || reset
    O_start = [20, 20, 35];           % mm  (varieren !)
    M_st = [0, 0, 0.4];             % A*m^2 (varieren !)
    p = [O_start / abstand, M_st / moment_skala];
    % Konstant 1 % des jeweiligen Startwerts. Bei Nullkomponenten wird
    % der Anfangsbetrag des zugehoerigen Vektors als Referenz verwendet.
    referenz_O = abs(O_start);
    referenz_M = abs(M_st);
    referenz_O(referenz_O == 0) = max(norm(O_start), abstand);
    referenz_M(referenz_M == 0) = max(norm(M_st), moment_skala);
    schritt_max = 0.02 * [referenz_O / abstand, referenz_M / moment_skala]; % 0.0x = x Prozent Kann jusitert werden.
  end

  % Reines Try-and-Error: alle sechs Komponenten zufaellig aendern.
  % Gleichverteilung in [-1 %, +1 %], stets relativ zum Anfang.
  B_alt = dipolfeld(p, sensoren, abstand, moment_skala);
  % 
  kandidat = p + (2*rand(1,6) - 1) .* schritt_max;
  % Unterhalb der z-Grenze wird der Versuch verworfen. Andere Seite des Arry
  if kandidat(3) >= 0.1
    B_neu = dipolfeld(kandidat, sensoren, abstand, moment_skala);
    if sum((B_neu(:) - B_mess(:)).^2) < sum((B_alt(:) - B_mess(:)).^2)
      p = kandidat;
      B_alt = B_neu;
    end
  end

  O = p(1:3) * abstand;
  M = p(4:6) * moment_skala;
  B_hyp = B_alt;
  fehler = sqrt(mean((B_hyp(:) - B_mess(:)).^2));
end




function B = dipolfeld(p, sensoren, abstand, moment_skala)
  O = p(1:3) * abstand;
  M = p(4:6) * moment_skala;
  R = bsxfun(@minus, sensoren, O) * 1e-3; % mm -> m fuer SI-Feldformel
  r2 = sum(R.^2, 2);
  % mu_0/(4*pi) = 1e-7 in SI-Einheiten.
  B = 1e-7 * (bsxfun(@times, R, 3*(R*M') ./ r2.^(5/2)) ...
               - bsxfun(@rdivide, repmat(M, 64, 1), r2.^(3/2)));
end
