SET client_encoding = 'UTF8';

DROP SCHEMA IF EXISTS dw CASCADE;
CREATE SCHEMA dw;
COMMENT ON SCHEMA dw IS 'Data Warehouse. Modelo dimensional (constelacao) da base Olist.';

CREATE OR REPLACE FUNCTION dw.fn_padroniza_texto(p_texto TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT NULLIF(
             REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
               INITCAP(
                 regexp_replace(
                   translate(lower(trim(p_texto)),
                             'áàâãäéèêëíìîïóòôõöúùûüçñ',
                             'aaaaaeeeeiiiiooooouuuucn'),
                   '\s+', ' ', 'g')),
               ' Do ', ' do '), ' Da ', ' da '), ' De ', ' de '),
               ' Dos ', ' dos '), ' Das ', ' das '), ' E ', ' e '),
             '');
$$;
COMMENT ON FUNCTION dw.fn_padroniza_texto(TEXT) IS
    'Padroniza texto (trim, caixa, acentos e espacos) para atributos descritivos das dimensoes.';

CREATE TABLE dw.aux_uf_regiao (
    uf          CHAR(2)     PRIMARY KEY,
    nome_estado VARCHAR(30) NOT NULL,
    regiao      VARCHAR(15) NOT NULL
);
COMMENT ON TABLE dw.aux_uf_regiao IS 'Tabela auxiliar UF -> nome do estado e regiao geografica (IBGE).';

INSERT INTO dw.aux_uf_regiao (uf, nome_estado, regiao) VALUES
    ('AC', 'Acre',                'Norte'),
    ('AL', 'Alagoas',             'Nordeste'),
    ('AM', 'Amazonas',            'Norte'),
    ('AP', 'Amapá',               'Norte'),
    ('BA', 'Bahia',               'Nordeste'),
    ('CE', 'Ceará',               'Nordeste'),
    ('DF', 'Distrito Federal',    'Centro-Oeste'),
    ('ES', 'Espírito Santo',      'Sudeste'),
    ('GO', 'Goiás',               'Centro-Oeste'),
    ('MA', 'Maranhão',            'Nordeste'),
    ('MG', 'Minas Gerais',        'Sudeste'),
    ('MS', 'Mato Grosso do Sul',  'Centro-Oeste'),
    ('MT', 'Mato Grosso',         'Centro-Oeste'),
    ('PA', 'Pará',                'Norte'),
    ('PB', 'Paraíba',             'Nordeste'),
    ('PE', 'Pernambuco',          'Nordeste'),
    ('PI', 'Piauí',               'Nordeste'),
    ('PR', 'Paraná',              'Sul'),
    ('RJ', 'Rio de Janeiro',      'Sudeste'),
    ('RN', 'Rio Grande do Norte', 'Nordeste'),
    ('RO', 'Rondônia',            'Norte'),
    ('RR', 'Roraima',             'Norte'),
    ('RS', 'Rio Grande do Sul',   'Sul'),
    ('SC', 'Santa Catarina',      'Sul'),
    ('SE', 'Sergipe',             'Nordeste'),
    ('SP', 'São Paulo',           'Sudeste'),
    ('TO', 'Tocantins',           'Norte');
