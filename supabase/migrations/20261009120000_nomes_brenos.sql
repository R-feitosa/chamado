-- Grafia correta dos nomes (confirmada pelo gestor em 09/10/2026; "Brenno Azevedo" bate com hub.pessoas).
-- Só o nome muda: cada pessoa mantém id, login, chamados e XP.
update chamados.pessoas set nome = 'Brenno Azevedo' where nome = 'Breno Azevedo' and papel = 'dev';
update chamados.pessoas set nome = 'Breno Magalhães' where nome = 'Brenno Magalhães' and papel = 'dev';
